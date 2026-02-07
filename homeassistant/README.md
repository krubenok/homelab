# Home Assistant config (live baseline)

This folder is synced from the running Home Assistant OS VM at `10.1.1.16` and is intended to represent `/config` as code.

## Scope
- Version controlled: YAML config, automations, scripts, scenes, blueprints, ESPHome files, custom components.
- Excluded: runtime/state/logs, databases, and secrets.

## Secrets model
- Home Assistant secrets stay in `secrets.yaml` on the VM (not committed).
- Zigbee2MQTT active config is intentionally not committed:
  - ignored: `zigbee2mqtt/configuration.yaml`
  - template: `zigbee2mqtt/configuration.example.yaml`

## Deploy mechanism
Home Assistant’s official `core_git_pull` add-on is the most native option, but in this VM it proved unsafe:
- when it decides the repo “doesn’t exist”, it will `git clone` into `/config` (destructive overwrite)
- it can also hit git safety checks (`detected dubious ownership`) inside the add-on container

Recommended approach here: pull via SSH (safe, explicit, and works with this VM’s ownership model):
- publish deploy branch: `scripts/publish_homeassistant_branch.sh u-kyrubeno-ha-config origin`
- deploy to HA VM: `git fetch/checkout/reset` in `/homeassistant` followed by `ha core check`

## Deploy branch (monorepo workaround)
This repo is a monorepo, but `core_git_pull` expects the repo root to map to `/config`.

We publish a dedicated deploy branch where the *branch root* is the HA `/config` directory:
- Publish script: `scripts/publish_homeassistant_branch.sh`
- Deploy branch name: `u-kyrubeno-ha-config`
- GitHub Actions: `Publish Home Assistant Deploy Branch` keeps the deploy branch up to date on every push to `main`.

## Safe update workflow
1. Edit files in `homeassistant/`.
2. Open a PR (recommended): CI runs `check_config` in a Home Assistant container matching `homeassistant/.HA_VERSION`.
3. Merge to `main`:
   - CI publishes the deploy branch (`u-kyrubeno-ha-config`).
4. On HA, pull the deploy branch via SSH:
   - `cd /homeassistant && git fetch origin u-kyrubeno-ha-config && git checkout -B u-kyrubeno-ha-config origin/u-kyrubeno-ha-config && git reset --hard origin/u-kyrubeno-ha-config`
5. Validate/restart on HA only after the pull succeeds:
   - `ha core check`
   - `ha core restart`
