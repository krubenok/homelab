#!/usr/bin/env bash
set -euo pipefail

# Deploy Home Assistant config to the HA OS VM using an SSH-driven git pull.
#
# Why: the official `core_git_pull` add-on can be destructive if it decides the
# repo doesn't exist and performs a clone into /config. This script is explicit
# and uses the host's git directly.

host="${1:-10.1.1.16}"
branch="${2:-u-kyrubeno-ha-config}"
remote="${3:-origin}"
restart="${RESTART_HA:-0}"
publish="${PUBLISH_DEPLOY_BRANCH:-1}"

repo_root="$(git rev-parse --show-toplevel)"

if [[ "${publish}" == "1" ]]; then
  "${repo_root}/scripts/publish_homeassistant_branch.sh" "${branch}" "${remote}"
fi

ssh -o StrictHostKeyChecking=accept-new "root@${host}" \
  "bash -lc 'set -euo pipefail; \
    cd /homeassistant; \
    git fetch ${remote} ${branch}; \
    git checkout -B ${branch} ${remote}/${branch}; \
    git reset --hard ${remote}/${branch}; \
    ha core check; \
    if [[ ${restart} == 1 ]]; then ha core restart; fi'"

echo "OK: deployed ${branch} to ${host}"
if [[ "${restart}" != "1" ]]; then
  echo "Note: set RESTART_HA=1 to restart Home Assistant after a successful check."
fi
