#!/usr/bin/env bash
set -euo pipefail

# Fetch a Home Assistant OS backup tarball from /backup/<slug>.tar via scp.
#
# Usage:
#   ./fetch_backup_tar.sh <host> <slug> [dest_dir]

host="${1:-}"
slug="${2:-}"
dest_dir="${3:-.}"

if [[ -z "${host}" || -z "${slug}" ]]; then
  echo "Usage: $0 <host> <slug> [dest_dir]" >&2
  exit 2
fi

mkdir -p "${dest_dir}"

remote_path="/backup/${slug}.tar"
local_path="${dest_dir%/}/${slug}.tar"

scp -o StrictHostKeyChecking=accept-new "root@${host}:${remote_path}" "${local_path}"

echo "OK: ${local_path}"

