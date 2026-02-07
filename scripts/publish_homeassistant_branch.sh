#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
config_dir="${repo_root}/homeassistant"
branch_name="${1:-u-kyrubeno-ha-config}"
remote_name="${2:-origin}"

if [[ ! -d "${config_dir}" ]]; then
  echo "Missing ${config_dir}" >&2
  exit 1
fi

if [[ "${branch_name}" == *"/"* ]] && [[ "${ALLOW_SLASH_BRANCH:-0}" != "1" ]]; then
  echo "Refusing to publish to branch '${branch_name}' because it contains '/'. Use a slash-free name (recommended for HA core_git_pull)." >&2
  echo "If you really want this, re-run with ALLOW_SLASH_BRANCH=1." >&2
  exit 2
fi

remote_url="$(git -C "${repo_root}" remote get-url "${remote_name}")"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

# Build a deploy tree that matches /config root and excludes local-only secrets/runtime.
rsync -a --delete \
  --exclude ".git/" \
  --exclude ".storage/" \
  --exclude "deps/" \
  --exclude "tts/" \
  --exclude "home-assistant.log*" \
  --exclude "*.db" \
  --exclude "*.db-shm" \
  --exclude "*.db-wal" \
  --exclude ".ha_run.lock" \
  --exclude "secrets.yaml" \
  --exclude "secrets.yaml.*" \
  --exclude "secrets.example.yaml" \
  --exclude ".cloud/" \
  --exclude ".ssh/" \
  --exclude "tesla_fleet.key" \
  --exclude "**/__pycache__/" \
  --exclude "**/*.pyc" \
  --exclude ".DS_Store" \
  --exclude "._*" \
  --exclude "zigbee2mqtt/log/" \
  --exclude "zigbee2mqtt/state.json" \
  --exclude "zigbee2mqtt/database.db" \
  --exclude "zigbee2mqtt/coordinator_backup.json" \
  --exclude "zigbee2mqtt/configuration.yaml" \
  --exclude "backups/" \
  --exclude "AGENTS.md" \
  --exclude "README.md" \
  "${config_dir}/" "${tmp_dir}/"

git -C "${tmp_dir}" init -q
git -C "${tmp_dir}" checkout -q -b "${branch_name}"
git -C "${tmp_dir}" config user.name "homelab-bot"
git -C "${tmp_dir}" config user.email "homelab-bot@local"
git -C "${tmp_dir}" add .

if git -C "${tmp_dir}" diff --cached --quiet; then
  echo "No files to publish for ${branch_name}."
  exit 0
fi

git -C "${tmp_dir}" commit -q -m "Publish Home Assistant config $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git -C "${tmp_dir}" remote add "${remote_name}" "${remote_url}"
git -C "${tmp_dir}" push -f "${remote_name}" "${branch_name}:${branch_name}"

echo "Published ${branch_name} to ${remote_url}"
