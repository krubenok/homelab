#!/usr/bin/env bash
set -euo pipefail

# Fetch a Home Assistant OS backup tarball off the VM for offline recovery.
#
# HA OS stores backups under /backup/*.tar. There's no `ha backups download` in
# the current CLI; use scp to copy the tar off the VM.

host="${1:-10.1.1.16}"
slug="${2:-}"

if [[ -z "${slug}" ]]; then
  echo "Usage: $0 <host> <backup-slug>" >&2
  echo "Example: $0 10.1.1.16 bb5cf38c" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel)"
dest_dir="${repo_root}/homeassistant/backups"
mkdir -p "${dest_dir}"

remote_path="/backup/${slug}.tar"
local_path="${dest_dir}/${slug}.tar"

echo "Checking remote backup exists: root@${host}:${remote_path}"
ssh -o StrictHostKeyChecking=accept-new "root@${host}" "test -f '${remote_path}'"

echo "Copying backup to: ${local_path}"
scp -o StrictHostKeyChecking=accept-new "root@${host}:${remote_path}" "${local_path}"

if command -v shasum >/dev/null 2>&1; then
  echo "Local sha256:"
  shasum -a 256 "${local_path}"
elif command -v sha256sum >/dev/null 2>&1; then
  echo "Local sha256:"
  sha256sum "${local_path}"
fi

echo "OK: ${local_path}"

