#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "websockets",
#   "pyyaml",
# ]
# ///
import argparse
import asyncio
import json
import os
import re
import ssl
import sys
import inspect
from urllib.parse import urlparse, urlunparse
from pathlib import Path
from typing import Dict, Optional

try:
    import websockets
except ImportError as exc:
    print(
        "error: missing dependency 'websockets' (run with `uv run --script`)",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc

try:
    import yaml
except ImportError as exc:
    print(
        "error: missing dependency 'pyyaml' (run with `uv run --script`)",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc


APP_NAME_RE = re.compile(r"^[a-z]([-a-z0-9]*[a-z0-9])?$")
ENV_VAR_RE = re.compile(r"\$\$|\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*")


def normalize_app_name(name: str) -> str:
    normalized = re.sub(r"[^a-z0-9-]", "-", name.lower())
    normalized = re.sub(r"-{2,}", "-", normalized).strip("-")
    return normalized


def load_compose_files(docker_dir: Path, allow_empty: bool = False) -> Dict[str, str]:
    if not docker_dir.exists():
        raise FileNotFoundError(f"Compose directory not found: {docker_dir}")

    files = sorted(docker_dir.glob("*.yml")) + sorted(docker_dir.glob("*.yaml"))
    if not files and not allow_empty:
        raise FileNotFoundError(f"No compose files found in {docker_dir}")

    stacks: Dict[str, str] = {}
    for path in files:
        name = normalize_app_name(path.stem)
        if not APP_NAME_RE.match(name):
            raise ValueError(f"Invalid app name from {path.name}: {name}")
        stacks[name] = path.read_text()
    return stacks


def build_ws_url(host: str, scheme: str, port: Optional[int]) -> str:
    if scheme not in {"ws", "wss"}:
        raise ValueError("scheme must be ws or wss")
    if port:
        return f"{scheme}://{host}:{port}/websocket"
    return f"{scheme}://{host}/websocket"


def normalize_ws_url(value: str) -> str:
    parsed = urlparse(value)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"Invalid TRUENAS_HOST/URL: {value}")
    scheme_map = {"http": "ws", "https": "wss", "ws": "ws", "wss": "wss"}
    ws_scheme = scheme_map.get(parsed.scheme)
    if not ws_scheme:
        raise ValueError(f"Unsupported URL scheme: {parsed.scheme}")
    path = parsed.path or "/websocket"
    return urlunparse((ws_scheme, parsed.netloc, path, "", parsed.query, ""))


def redact_secrets(obj):
    if isinstance(obj, dict):
        redacted = {}
        for key, value in obj.items():
            if isinstance(key, str) and re.search(
                r"(pass(word)?|token|secret|key)$", key, re.IGNORECASE
            ):
                redacted[key] = "<redacted>"
            else:
                redacted[key] = redact_secrets(value)
        return redacted
    if isinstance(obj, list):
        return [redact_secrets(item) for item in obj]
    return obj


def _resolve_var(name: str, env: Dict[str, str], strict: bool, missing: set) -> str:
    if name in env:
        return env[name]
    missing.add(name)
    if strict:
        raise ValueError(f"Missing env var: {name}")
    return ""


def _resolve_expr(expr: str, env: Dict[str, str], strict: bool, missing: set) -> str:
    for op in (":-", "-", ":?", "?"):
        if op in expr:
            var, default = expr.split(op, 1)
            var = var.strip()
            if op == ":-":
                value = env.get(var)
                if value:
                    return value
                return default
            if op == "-":
                if var in env:
                    return env[var]
                return default
            if op == ":?":
                value = env.get(var)
                if value:
                    return value
                raise ValueError(default or f"Missing required env var: {var}")
            if op == "?":
                if var in env:
                    return env[var]
                raise ValueError(default or f"Missing required env var: {var}")
    return _resolve_var(expr.strip(), env, strict, missing)


def expand_env_vars(text: str, env: Dict[str, str], strict: bool) -> tuple[str, set]:
    missing: set[str] = set()

    def replace(match: re.Match) -> str:
        token = match.group(0)
        if token == "$$":
            return "$"
        if token.startswith("${"):
            expr = token[2:-1]
            return _resolve_expr(expr, env, strict, missing)
        return _resolve_var(token[1:], env, strict, missing)

    return ENV_VAR_RE.sub(replace, text), missing


class RpcClient:
    def __init__(self, ws):
        self._ws = ws
        self._next_id = 1

    async def call(self, method: str, params=None):
        if params is None:
            params = []
        req_id = self._next_id
        self._next_id += 1
        payload = {"id": req_id, "msg": "method", "method": method, "params": params}
        await self._ws.send(json.dumps(payload))
        while True:
            raw = await self._ws.recv()
            msg = json.loads(raw)
            if msg.get("id") != req_id:
                continue
            if "error" in msg:
                raise RuntimeError(msg["error"])
            return msg.get("result")


async def run(args: argparse.Namespace) -> int:
    docker_dir = Path(args.docker_dir)
    stacks = load_compose_files(docker_dir, allow_empty=args.pull_missing)
    if args.expand_env:
        missing_vars: set[str] = set()
        for name, compose in stacks.items():
            expanded, missing = expand_env_vars(
                compose, dict(os.environ), args.expand_env_strict
            )
            stacks[name] = expanded
            missing_vars.update(missing)
        if missing_vars and not args.expand_env_strict:
            missing_list = ", ".join(sorted(missing_vars))
            print(
                f"warning: missing env vars expanded to empty strings: {missing_list}",
                file=sys.stderr,
            )

    if args.url:
        ws_url = args.url
    else:
        host = args.host or os.environ.get("TRUENAS_HOST")
        if not host:
            raise ValueError("Missing --host or TRUENAS_HOST")
        host = host.strip()
        if "://" in host:
            ws_url = normalize_ws_url(host)
        else:
            scheme = args.scheme or os.environ.get("TRUENAS_SCHEME", "wss")
            port = args.port
            ws_url = build_ws_url(host, scheme, port)

    username = args.username or os.environ.get("TRUENAS_USER")
    api_key = args.api_key or os.environ.get("TRUENAS_API_KEY")
    if not username or not api_key:
        raise ValueError("Missing --username/--api-key or TRUENAS_USER/TRUENAS_API_KEY")

    ssl_ctx = None
    if ws_url.startswith("wss://"):
        if args.insecure:
            ssl_ctx = ssl._create_unverified_context()
        else:
            ssl_ctx = ssl.create_default_context()

    headers = {}
    cf_access_token = os.environ.get("CF_ACCESS_TOKEN")
    cf_access_client_id = os.environ.get("CF_ACCESS_CLIENT_ID")
    cf_access_client_secret = os.environ.get("CF_ACCESS_CLIENT_SECRET")
    if cf_access_client_id:
        cf_access_client_id = cf_access_client_id.replace("CF-Access-Client-Id:", "").strip()
    if cf_access_client_secret:
        cf_access_client_secret = cf_access_client_secret.replace(
            "CF-Access-Client-Secret:", ""
        ).strip()
    if cf_access_token:
        headers["cf-access-token"] = cf_access_token
    elif cf_access_client_id or cf_access_client_secret:
        if not (cf_access_client_id and cf_access_client_secret):
            raise ValueError(
                "Both CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET are required."
            )
        headers["CF-Access-Client-Id"] = cf_access_client_id
        headers["CF-Access-Client-Secret"] = cf_access_client_secret

    connect_kwargs = {
        "ssl": ssl_ctx,
        "max_size": 10 * 1024 * 1024,
    }
    if headers:
        try:
            params = inspect.signature(websockets.connect).parameters
        except (TypeError, ValueError):
            params = {}
        if "additional_headers" in params:
            connect_kwargs["additional_headers"] = headers
        else:
            connect_kwargs["extra_headers"] = headers

    async with websockets.connect(ws_url, **connect_kwargs) as ws:
        await ws.send(json.dumps({"msg": "connect", "version": "1", "support": ["1"]}))
        connect_msg = json.loads(await ws.recv())
        if connect_msg.get("msg") != "connected":
            raise RuntimeError(f"Unexpected connect response: {connect_msg}")

        rpc = RpcClient(ws)
        login = await rpc.call(
            "auth.login_ex",
            [
                {
                    "mechanism": "API_KEY_PLAIN",
                    "username": username,
                    "api_key": api_key,
                    "login_options": {"user_info": False},
                }
            ],
        )
        if login.get("response_type") != "SUCCESS":
            raise RuntimeError(f"Login failed: {login}")

        apps = await rpc.call("app.query")
        apps_by_name = {app["name"]: app for app in apps}

        for name, compose in stacks.items():
            action = "create" if name not in apps_by_name else "update"
            if args.dry_run:
                print(f"[dry-run] {action} {name}")
                continue

            if action == "create":
                await rpc.call(
                    "app.create",
                    [
                        {
                            "app_name": name,
                            "custom_app": True,
                            "custom_compose_config_string": compose,
                        }
                    ],
                )
                print(f"created {name}")
            else:
                existing = apps_by_name[name]
                if not existing.get("custom_app", False):
                    raise RuntimeError(f"App {name} exists but is not a custom app")
                await rpc.call(
                    "app.update",
                    [
                        name,
                        {"custom_compose_config_string": compose},
                    ],
                )
                print(f"updated {name}")

        if args.pull_missing:
            export_dir = Path(args.pull_dir)
            export_dir.mkdir(parents=True, exist_ok=True)
            for name, app in apps_by_name.items():
                if not app.get("custom_app", False):
                    continue
                if name in stacks:
                    continue
                out_path = export_dir / f"{name}.yml"
                if out_path.exists() and not args.pull_overwrite:
                    continue
                if args.dry_run:
                    print(f"[dry-run] pull {name} -> {out_path}")
                    continue
                config = await rpc.call("app.config", [name])
                if not args.pull_raw:
                    config = redact_secrets(config)
                yaml_text = yaml.safe_dump(config, sort_keys=False)
                out_path.write_text(yaml_text, encoding="utf-8")
                stacks[name] = yaml_text
                print(f"pulled {name} -> {out_path}")

        if args.delete_missing:
            stack_names = set(stacks.keys())
            for name, app in apps_by_name.items():
                if not app.get("custom_app", False):
                    continue
                if name in stack_names:
                    continue
                if args.dry_run:
                    print(f"[dry-run] delete {name}")
                    continue
                await rpc.call("app.delete", [name])
                print(f"deleted {name}")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync TrueNAS custom apps from local compose files."
    )
    parser.add_argument("--docker-dir", default="docker")
    parser.add_argument("--host")
    parser.add_argument("--scheme", choices=["ws", "wss"])
    parser.add_argument("--port", type=int)
    parser.add_argument(
        "--url", help="Full websocket URL, e.g. wss://truenas/websocket"
    )
    parser.add_argument("--username")
    parser.add_argument("--api-key")
    parser.add_argument("--insecure", action="store_true", help="Skip TLS verification")
    parser.add_argument("--delete-missing", action="store_true")
    parser.add_argument("--pull-missing", action="store_true")
    parser.add_argument("--pull-overwrite", action="store_true")
    parser.add_argument("--pull-raw", action="store_true")
    parser.add_argument("--pull-dir", default="docker")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--expand-env",
        dest="expand_env",
        action="store_true",
        help="Expand environment variables in compose files (default).",
    )
    parser.add_argument(
        "--no-expand-env",
        dest="expand_env",
        action="store_false",
        help="Disable environment variable expansion.",
    )
    parser.add_argument(
        "--expand-env-strict",
        action="store_true",
        help="Fail if required env vars are missing during expansion.",
    )
    parser.set_defaults(expand_env=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        return asyncio.run(run(args))
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
