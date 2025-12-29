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
- Power: migrated to Chungus; ready to export/retire (legacy 2x raidz2: 6x 16.4T + 6x 12.7T)
- boot-pool: mirror (sds3 + sdv3), ~928G total

## Migration status
- Media moved to /mnt/Chungus/Media/Movies and /mnt/Chungus/Media/TV
- Files moved to /mnt/Chungus/Users/krubenok
- TimeMachine moved to /mnt/Chungus/Backups/TimeMachine (tm + krubenok)
- Incremental catch-up complete; Power export pending

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
