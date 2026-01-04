#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
run_name="${1:-}"
safe_run_name=""
if [[ -n "${run_name}" ]]; then
  safe_run_name="${run_name//[^A-Za-z0-9._-]/_}"
  while [[ "${safe_run_name}" == *"__"* ]]; do
    safe_run_name="${safe_run_name//__/_}"
  done
  safe_run_name="${safe_run_name#_}"
  safe_run_name="${safe_run_name%_}"
fi
if [[ -n "${TS_OUT:-}" ]]; then
  out_file="${TS_OUT}"
elif [[ -n "${safe_run_name}" ]]; then
  out_file="${repo_root}/tmp/tailscale-exitnode-dns-diag-${safe_run_name}.txt"
else
  out_file="${repo_root}/tmp/tailscale-exitnode-dns-diag.txt"
fi
include_debug_prefs="${TS_INCLUDE_DEBUG_PREFS:-0}"

run_cmd() {
  local label="$1"
  shift

  {
    echo "## ${label}"
    echo "\$ $*"
  } >> "${out_file}"

  if "$@" >> "${out_file}" 2>&1; then
    echo >> "${out_file}"
  else
    local status=$?
    echo "Command failed (exit ${status})." >> "${out_file}"
    echo >> "${out_file}"
    return 0
  fi
}

if ! command -v tailscale >/dev/null 2>&1; then
  echo "tailscale CLI not found in PATH." >&2
  exit 1
fi

mkdir -p "$(dirname "${out_file}")"

{
  echo "# Tailscale Exit-Node DNS Diagnostics"
  echo
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Host: $(hostname)"
  if [[ -n "${run_name}" ]]; then
    echo "Run name: ${run_name}"
  fi
  if command -v sw_vers >/dev/null 2>&1; then
    sw_vers
  else
    uname -a
  fi
  echo
} > "${out_file}"

run_cmd "tailscale version" tailscale version
run_cmd "tailscale status" tailscale status
run_cmd "tailscale status --self" tailscale status --self
run_cmd "tailscale status --json" tailscale status --json
run_cmd "tailscale ip -4" tailscale ip -4
run_cmd "tailscale ip -6" tailscale ip -6
run_cmd "tailscale dns status" tailscale dns status
run_cmd "tailscale exit-node list" tailscale exit-node list
run_cmd "tailscale netcheck" tailscale netcheck
run_cmd "tailscale serve status" tailscale serve status
run_cmd "tailscale funnel status" tailscale funnel status
run_cmd "tailscale appc-routes" tailscale appc-routes

if command -v scutil >/dev/null 2>&1; then
  run_cmd "scutil --dns" scutil --dns
fi

if command -v networksetup >/dev/null 2>&1; then
  run_cmd "networksetup -listallnetworkservices" networksetup -listallnetworkservices
  while IFS= read -r service; do
    if [[ -n "${service}" && "${service}" != "An asterisk (*) denotes that a network service is disabled." ]]; then
      run_cmd "networksetup -getdnsservers ${service}" networksetup -getdnsservers "${service}"
    fi
  done < <(networksetup -listallnetworkservices | tail -n +2)
fi

if command -v route >/dev/null 2>&1; then
  run_cmd "route -n get default" route -n get default
fi

if command -v python3 >/dev/null 2>&1; then
  {
    echo "## resolver checks"
    echo "\$ python3 (resolver extraction + classification)"
    python3 - <<'PY'
import ipaddress
import subprocess

def get_resolvers():
    out = subprocess.check_output(["tailscale", "dns", "status"], text=True)
    resolvers = []
    in_resolvers = False
    for line in out.splitlines():
        if line.startswith("Resolvers"):
            in_resolvers = True
            continue
        if line.startswith("Split DNS Routes"):
            in_resolvers = False
        if in_resolvers and line.strip().startswith("-"):
            parts = line.split()
            if len(parts) >= 2:
                resolvers.append(parts[1])
    return resolvers

def classify(ip_str):
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return "unknown"
    if ip.version == 4 and ip in ipaddress.ip_network("100.64.0.0/10"):
        return "tailscale-cgnat"
    if ip.is_private:
        return "private"
    if ip.is_loopback:
        return "loopback"
    if ip.is_global:
        return "public"
    return "other"

resolvers = get_resolvers()
if not resolvers:
    print("No resolvers found in tailscale dns status.")
else:
    print("Resolvers:")
    for r in resolvers:
        print(f"  - {r} ({classify(r)})")
PY
    echo
  } >> "${out_file}"
fi

resolvers=()
if command -v awk >/dev/null 2>&1; then
  while IFS= read -r resolver; do
    [[ -n "${resolver}" ]] && resolvers+=("${resolver}")
  done < <(
    tailscale dns status 2>/dev/null | awk '
      /^Resolvers/ {in_resolvers=1; next}
      /^Split DNS Routes/ {in_resolvers=0}
      in_resolvers && $1=="-" {print $2}
    '
  )
fi

if [[ ${#resolvers[@]} -gt 0 ]]; then
  for resolver in "${resolvers[@]}"; do
    is_ipv6=0
    if [[ "${resolver}" == *:* ]]; then
      is_ipv6=1
    fi
    if [[ "${is_ipv6}" == "1" ]]; then
      if command -v ping6 >/dev/null 2>&1; then
        run_cmd "ping6 -c 2 ${resolver}" ping6 -c 2 "${resolver}"
      else
        run_cmd "ping -c 2 -6 ${resolver}" ping -c 2 -6 "${resolver}"
      fi
    else
      run_cmd "ping -c 2 ${resolver}" ping -c 2 "${resolver}"
    fi
    if command -v nc >/dev/null 2>&1; then
      run_cmd "nc -vz -w 2 ${resolver} 53 (tcp)" nc -vz -w 2 "${resolver}" 53
      run_cmd "nc -vz -w 2 -u ${resolver} 53 (udp)" nc -vz -w 2 -u "${resolver}" 53
    fi
    if command -v dig >/dev/null 2>&1; then
      run_cmd "dig +time=2 +tries=1 @${resolver} example.com" dig +time=2 +tries=1 @"${resolver}" example.com
    elif command -v nslookup >/dev/null 2>&1; then
      run_cmd "nslookup example.com ${resolver}" nslookup example.com "${resolver}"
    fi
    if command -v route >/dev/null 2>&1; then
      if [[ "${is_ipv6}" == "1" ]]; then
        run_cmd "route -n get -inet6 ${resolver}" route -n get -inet6 "${resolver}"
      else
        run_cmd "route -n get ${resolver}" route -n get "${resolver}"
      fi
    fi
  done
fi

if [[ "${include_debug_prefs}" == "1" ]]; then
  run_cmd "tailscale debug prefs" tailscale debug prefs
fi

{
  echo "## notes"
  echo "- Run this while connected to an exit node."
  echo "- If resolvers are RFC1918/private (e.g., 10.x/192.168.x), confirm the DNS server is reachable via a subnet route or use its Tailscale IP."
  echo "- If exit node is enabled, default route should point at the Tailscale interface and DNS queries should succeed against the tailnet resolver."
  echo
} >> "${out_file}"

echo "Wrote ${out_file}"
