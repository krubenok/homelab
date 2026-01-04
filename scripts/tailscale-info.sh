#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
out_file="${TS_OUT:-${repo_root}/tmp/tailscale-info.txt}"
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
  echo "# Tailscale Info"
  echo
  echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "Host: $(hostname)"
  if command -v sw_vers >/dev/null 2>&1; then
    sw_vers
  else
    uname -a
  fi
  echo
} > "${out_file}"

run_cmd "tailscale version" tailscale version
run_cmd "tailscale status" tailscale status
run_cmd "tailscale status --json" tailscale status --json
run_cmd "tailscale status --self" tailscale status --self
run_cmd "tailscale ip -4" tailscale ip -4
run_cmd "tailscale ip -6" tailscale ip -6
run_cmd "tailscale netcheck" tailscale netcheck
run_cmd "tailscale dns status" tailscale dns status
run_cmd "tailscale exit-node list" tailscale exit-node list
run_cmd "tailscale serve status" tailscale serve status
run_cmd "tailscale funnel status" tailscale funnel status
run_cmd "tailscale appc-routes" tailscale appc-routes

if [[ "${include_debug_prefs}" == "1" ]]; then
  run_cmd "tailscale debug prefs" tailscale debug prefs
fi

echo "Wrote ${out_file}"
