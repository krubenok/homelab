# Home Assistant repo notes (captured 2026-02-07)

## Current state
- This `homeassistant/` directory appears to be a mirror/snapshot of `/config` from HA OS.
- `homeassistant/.HA_VERSION` is `2025.12.5`.
- Baseline was refreshed from live VM (`10.1.1.16`) on 2026-02-07 via `tar` over SSH.
- Approximate footprint:
  - `homeassistant/` (repo working tree): ~82 MB

## GitOps workflow (implemented)
- Monorepo reality: HA config lives under `homeassistant/`, but HA `core_git_pull` expects repo root == `/config`.
- Deploy branch workaround: publish a dedicated branch whose branch root is the HA `/config` tree:
  - Script: `scripts/publish_homeassistant_branch.sh`
  - Branch: `u-kyrubeno-ha-config` (slash-free; recommended for tooling compatibility)
- CI:
  - `.github/workflows/homeassistant-check.yml` runs `check_config` in a Home Assistant container pinned to `homeassistant/.HA_VERSION`.
  - `.github/workflows/homeassistant-publish-deploy-branch.yml` publishes/updates the deploy branch on every push to `main`.

## Important findings
- Runtime/generated files are present and should not be versioned:
  - Python cache trees (`__pycache__/`, `*.pyc`)
  - Zigbee2MQTT rolling logs (`zigbee2mqtt/log/**`)
  - Runtime lock files (for example `.ha_run.lock`)
  - Runtime state snapshots (for example `zigbee2mqtt/state.json`)
- Live `/homeassistant` had no `.gitignore`; repo-local `homeassistant/.gitignore` now defines exclusions.
- Sensitive values are present in `homeassistant/zigbee2mqtt/configuration.yaml` (MQTT credentials and Zigbee network material). Treat this file as sensitive until secrets strategy is applied.

## GitOps direction (native-first)
- Prefer Home Assistant’s official **Git pull app/add-on** for pull-based deployment into `/config`.
- Keep YAML-first config in repo (`configuration.yaml`, `packages/`, automations/scripts/scenes, blueprints, selected integration configs).
- Keep secrets out of git using `!secret` and `secrets.yaml` (or external secret injection workflow).
- Validate before restart/reload with HA config check (`ha core check` on HA OS, or `hass --script check_config` in equivalent environment).

## Open challenges
- `core_git_pull` expects the repository root to map to `/config`. In this monorepo, HA config currently lives under `homeassistant/`; use a dedicated deploy branch with config at root.
- `zigbee2mqtt/configuration.yaml` contains secrets and network material; keep active file local-only and version a redacted template.
- Anything configured via UI ends up in `.storage/` and is state, not code. Keep it out of git; rely on HA backups for recovery.

## Incident log (2026-02-07)
- Attempted first `core_git_pull` run after configuring branch `u/kyrubeno/ha-config`.
- Add-on log showed:
  - clone executed
  - then script failed with `/run.sh: line 178: OLD_COMMIT: unbound variable`
- Result: `/homeassistant` was replaced with repository root content at least once, and critical runtime files were removed from disk (`.storage` registry/auth files and DB files).
- Immediate containment applied:
  - `core_git_pull` stopped
  - add-on boot mode set to `manual`
  - `/homeassistant` YAML/component tree restored from local baseline copy
  - non-config repo artifacts removed from `/homeassistant`
- Follow-up recovery steps:
  - Regenerated missing `.storage` registries by making targeted UI changes until the relevant `core.*` JSON files were recreated (entity/device/area/entries/config).
  - Kept `core_git_pull` in `manual` boot mode to prevent re-running clone logic accidentally.

## Recovery checkpoint (2026-02-07)
- Created partial backup (homeassistant folder, DB excluded):
  - Name: `pre-gitops-2026-02-07`
  - Slug: `bb5cf38c`
  - Created: `2026-02-07T21:03:23Z`
- Increased backup retention window (`days_until_stale`) to 180 days.

## Recovery recommendation
- Keep at least one backup off the HA VM (for example, download the `bb5cf38c` backup tar to this repo’s ignored `homeassistant/backups/` directory or to TrueNAS).
- Script helper (downloads `/backup/<slug>.tar` via scp):
  - `scripts/ha_fetch_backup.sh 10.1.1.16 bb5cf38c`
