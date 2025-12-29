# TrueNAS SCALE reference (truenas @ 10.1.1.3)

## Access
- SSH: ssh truenas_admin@10.1.1.3

## System
- TrueNAS: 25.10.0.1
- OS: Debian 12 (bookworm)
- Kernel: 6.12.33-production+truenas
- Hostname: truenas
- CPU: Intel i9-12900K (24 cores, 16 physical)
- RAM: 125.5 GiB, ECC: false
- TZ: America/Los_Angeles
- System dataset pool: Chungus (/var/db/system)
- Domain: local
- IPv4 gateway: 10.1.1.1
- DNS: 1.1.1.1, 10.1.1.2
- Service announcement: netbios, mdns, wsd enabled

## Pools
- Chungus: raidz2 (8x 23.6T), ~189T total, ~0% used
- FineBoi: 2x mirror vdevs (4 disks), ~3.67T total, ~8% used
- Power: migrated to Chungus and exported/retired (legacy 2x raidz2: 6x 16.4T + 6x 12.7T)
- boot-pool: mirror (sds3 + sdv3), ~928G total

## Migration status
- Media moved to /mnt/Chungus/Media/Movies and /mnt/Chungus/Media/TV
- Files moved to /mnt/Chungus/Users/krubenok
- TimeMachine moved to /mnt/Chungus/Backups/TimeMachine (tm + krubenok)
- Incremental catch-up complete; Power exported

## ZFS basics
- ashift: 12 on all pools
- autotrim: Chungus off, FineBoi on, Power off (legacy)
- recordsize: default 128K (exceptions: Chungus/Media, FineBoi/Downloads, FineBoi/Transcode at 1M)
- compression:
  - Chungus: lz4 at root; zstd-1 on Media/Users/Backups datasets
  - FineBoi: lz4 (some datasets received), Downloads off
  - Power: off at pool (legacy)
- atime: off broadly
- dedup: off
- zvols:
  - FineBoi/HomeAssistantOS: 32G volsize, 16K volblocksize

## Chungus dataset layout (current)
- Chungus/Users (parent)
- Chungus/Users/krubenok
- Chungus/Backups/TimeMachine (refquota 5T)
- Chungus/Media/Movies, Chungus/Media/TV
- Properties: Media recordsize=1M, compression=zstd-1; Users/Backups recordsize=128K, compression=zstd-1; atime=off

## ARC
- zfs_arc_min: 0 (auto)
- zfs_arc_max: 0 (auto)
- ARC c_max: ~124G
- ARC size: ~11.7G
- l2arc_noprefetch: 1

## Services
- Enabled + running: ssh
- Disabled/stopped: cifs, nfs, iscsitarget, snmp, ups, nvmet, ftp
- SMB config exists but service disabled; no SMB or NFS shares configured

## Apps (custom app containers)
- Running: tautulli, sabnzbd, radarr, sonarr, paperless, cloudflared, tailscale-gw
- Stopped: jackett
- App data: /mnt/FineBoi/Apps/*
- Media: /mnt/Chungus/Media/Movies, /mnt/Chungus/Media/TV
- Downloads: /mnt/FineBoi/Downloads
- ix-apps mount: /mnt/.ix-apps (FineBoi/ix-apps)

## Docker management (Dockge + git push deploy)
- Dockge app dir: /mnt/FineBoi/Apps/dockge
- Dockge stacks path: /mnt/FineBoi/Apps/homelab/docker
- Stack layout: Dockge expects /mnt/FineBoi/Apps/homelab/docker/<stack>/compose.yaml (move/rename existing docker/*.yml)
- After moving/renaming stacks, use Dockge "Scan Stacks Folder" to import them
- Dockge install:
  - mkdir -p /mnt/FineBoi/Apps/homelab/docker /mnt/FineBoi/Apps/dockge
  - cd /mnt/FineBoi/Apps/dockge
  - curl "https://dockge.kuma.pet/compose.yaml?port=5001&stacksPath=/mnt/FineBoi/Apps/homelab/docker" --output compose.yaml
  - docker compose up -d
- Dockge update:
  - cd /mnt/FineBoi/Apps/dockge
  - docker compose pull && docker compose up -d
- Auto-deploy on push to main (self-contained, no external CI):
  - Create a bare repo on the NAS (for example /mnt/FineBoi/Apps/homelab.git)
  - Add a post-receive hook that checks out main into /mnt/FineBoi/Apps/homelab and runs docker compose up -d per stack
  - Push from local to the NAS remote; the hook applies the update and Dockge reflects the new stack state
  - Example post-receive hook:
    - /mnt/FineBoi/Apps/homelab.git/hooks/post-receive
    - chmod +x /mnt/FineBoi/Apps/homelab.git/hooks/post-receive
    - contents:
      ```bash
      #!/usr/bin/env bash
      set -euo pipefail

      GIT_WORK_TREE=/mnt/FineBoi/Apps/homelab git checkout -f main

      for stack_dir in /mnt/FineBoi/Apps/homelab/docker/*; do
        [ -d "$stack_dir" ] || continue
        docker compose -f "$stack_dir/compose.yaml" up -d
      done
      ```
- API sync (no repo on NAS, uses API key):
  - Script: scripts/truenas_sync_apps.py
  - Uses uv inline script metadata (no manual install needed)
  - Uses WebSocket API auth.login_ex with API key
  - API key should have APPS_WRITE permissions
  - Env vars: TRUENAS_HOST, TRUENAS_USER, TRUENAS_API_KEY
  - App names are derived from docker/<name>.yml (lowercase, hyphens only)
  - 1Password CLI secret references (op://...) via env file:
    - Template: scripts/truenas_sync_apps.env.example
    - Copy to scripts/truenas_sync_apps.env
    - Run with 1Password CLI:
      - op run --env-file scripts/truenas_sync_apps.env -- uv run --script scripts/truenas_sync_apps.py --dry-run
  - Cloudflare Access (optional):
    - Env vars: CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET (or CF_ACCESS_TOKEN)
  - Compose env expansion:
    - ${VAR} and ${VAR:-default} are expanded locally before sync
    - Use --no-expand-env to keep placeholders, --expand-env-strict to fail on missing vars
    - Store app secrets in the env file (e.g., CLOUDFLARED_TUNNEL_TOKEN)
  - Example:
    - uv run --script scripts/truenas_sync_apps.py --dry-run
    - uv run --script scripts/truenas_sync_apps.py --delete-missing
    - uv run --script scripts/truenas_sync_apps.py --pull-missing
    - uv run --script scripts/truenas_sync_apps.py --pull-missing --pull-raw
  - Pulling from TrueNAS:
    - Uses app.config to write docker/<app>.yml for custom apps missing locally
    - Redacts likely secrets by default; use --pull-raw to keep values
    - Use --pull-overwrite to replace existing files, --pull-dir to change output
  - TrueNAS API key setup (UI):
    - Create a dedicated user with only the permissions needed for Apps
    - In the top-right user menu, open "My API Keys" (or Credentials > Users > View API Keys)
    - Add API Key and copy it immediately; the key is shown only once
    - API keys are user-linked and can be set to expire; they bypass 2FA
  - Use --url to set a full websocket URL, or --insecure for self-signed TLS

## VMs
- HomeAssistantOS: running, autostart, 2 vCPU, 2G RAM, VIRTIO disk on /dev/zvol/FineBoi/HomeAssistantOS, NIC on br1

## Disks (lsblk highlights)
- 23.6T: ST26000DM000 (sdd–sdn) -> Chungus
- 16.4T: WDC WD180EDGZ (sdo–sdr, sdt, sdu) -> Power raidz2-0
- 12.7T: ST14000NE0008 + WD140EDGZ (sda–sdh) -> Power raidz2-1
- Boot: sds (1T), sdv (1T)
- NVMe present: 1.4T Intel, 2x 2T WD SN750, 2x 1.9T Samsung (usage TBD)
- No log/cache vdevs visible in zpool status

## Tasks
- Scrubs: weekly (Chungus, FineBoi)
- Snapshots: none configured
- Replication: none configured

## Notes
- UI certificate/private key output was returned by midclt; avoid sharing.
- Created local group `media` (gid 1000) and added `truenas_admin` for access to media datasets.

## Optimization plan (draft)
- Target: keep media and backups on Chungus; apps/VMs on FineBoi.
- Special vdev: add a mirrored special metadata vdev to Chungus using two reliable SSDs (prefer PLP). This speeds up Plex/arr scans, directory listing, and small-file metadata operations.
- Special small blocks: keep at 0 for media datasets; consider 64K or 128K for Chungus/Users/* and Chungus/Backups to accelerate small-file workloads.
- Optane 1.36T: use as L2ARC (safe) if desired; consider as SLOG only if sync writes become heavy (SMB/NFS with sync/iSCSI).
- Intel 750 400GB (single device): suitable as L2ARC test device; not suitable for special vdev without a mirror.
- PCIe lanes: confirm link widths/speeds with sudo lspci before placing more NVMe devices.

## PCIe link status (current)
- HBA (LSI SAS3224): PCIe 3.0 x8 (8GT/s x8)
- NVMe devices: PCIe 3.0 x4 (8GT/s x4) across 5 controllers
- Optane 900P: PCIe 3.0 x4 (8GT/s x4)
