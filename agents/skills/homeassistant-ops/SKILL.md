---
name: homeassistant-ops
description: Home Assistant OS operations playbooks and recovery procedures. Use when operating, debugging, backing up/restoring, or recovering access to a Home Assistant OS instance (HA Supervisor/Core/add-ons), especially when the web UI is unavailable or authentication is broken.
---

# Home Assistant Ops

## Connection Playbook

Goal: obtain a control plane even if the UI is down.

Commands are run on the HA OS host unless noted.

1. Preferred: Home Assistant OS console (hypervisor VM console).
   - Log in as `root`.
   - `ha info`
2. SSH (via “Terminal & SSH” add-on).
   - `ssh -o StrictHostKeyChecking=accept-new root@<host>`
   - Verify: `ha core info`

Notes:
- HA OS commonly has `/config` as a symlink to the actual config directory (often `/homeassistant`).
- Avoid assuming Python/Docker CLIs exist on the HA OS host. Use `ha ...` subcommands.

## Triage Playbook (UI Not Working / Errors)

1. Check core status:
   - `ha core info`
2. Read logs:
   - `ha core logs | tail -n 200`
   - `ha supervisor logs | tail -n 200`
3. Validate config before restart:
   - `ha core check`
4. Restart core if needed:
   - `ha core restart`

## Backup Playbook

1. List backups:
   - `ha backups list`
2. Create a backup (recommend excluding DB unless you explicitly need history):
   - `ha backups new --name "<reason> <YYYY-MM-DD>" --homeassistant-exclude-database`
3. Backups on disk:
   - `ls -la /backup`
   - Files are typically `/backup/<slug>.tar`
4. Get an off-box copy (recommended):
   - `scp -o StrictHostKeyChecking=accept-new root@<host>:/backup/<slug>.tar ./`
   - Or use `scripts/fetch_backup_tar.sh`

Restore:
- `ha backups restore <slug> --homeassistant`

## Auth/Login Recovery Playbook

Use this when:
- you can reach HA, but login fails (often seen as repeated `/auth/login_flow/...` invalid auth in Core logs)
- or `.storage/auth` is missing/corrupted

### Step 1: Confirm Whether Auth Storage Exists

1. Stop core (reduces chance of partial writes during inspection):
   - `ha core stop`
2. Check storage directory:
   - `ls -la /config/.storage || ls -la /homeassistant/.storage`
   - If `.storage/auth` is missing, restoring a known-good backup is often fastest.
3. Start core if you didn’t restore yet:
   - `ha core start`

### Step 2: Password Reset (If Available)

On some systems, `ha authentication reset` is only allowed from the HA OS console (not from add-on SSH sessions).

- `ha auth list`
- `ha authentication reset --interactive`

If `ha authentication reset` is buggy or refuses to find the username, use onboarding reset below.

### Step 3: Onboarding Reset (Reliable, Destructive To Sessions)

This preserves your YAML/config, but resets authentication state:
- you will create a new owner user
- existing app sessions and long-lived tokens may need re-setup

1. Stop core:
   - `ha core stop`
2. Back up `.storage`:
   - `ts=$(date -u +%Y%m%dT%H%M%SZ)`
   - `cp -a /config/.storage "/config/.storage.bak.${ts}"` (or the equivalent under `/homeassistant`)
3. Move aside auth store and onboarding marker:
   - `mv /config/.storage/auth "/config/.storage/auth.broken.${ts}" || true`
   - `rm -f /config/.storage/onboarding || true`
4. Start core:
   - `ha core start`
5. Complete onboarding in the UI:
   - Prefer LAN URL first (`http://<LAN-IP>:8123`)
   - If behind a proxy/tunnel, use a private window and clear site data to avoid stale cookies.

Automation helper:
- (intentionally not scripted; do it manually and carefully)

## Safety Notes

- Treat `.storage/` as runtime/state. Do not version it in git.
- Before any risky change (git-based deploys, mass deletes, add-on experiments), create a backup and get an off-box copy.
