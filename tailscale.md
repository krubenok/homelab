# Tailscale Configuration (Local Mac)

## Local device
- Node name: work-macbook-pro
- OS: macOS 26.3 (25D5087f)
- Tailscale version: 1.93.56 (unstable/dev track)
- Tailscale IPs: 100.123.20.22, fd7a:115c:a1e0::5101:1416
- MagicDNS name: work-macbook-pro.terrier-tegus.ts.net
- Node key expiry: 2026-01-06T17:41:42Z
- Exit node: not enabled on this device

## Tailnet
- Name: rubenok.ca
- MagicDNS: enabled
- MagicDNS suffix: terrier-tegus.ts.net

## DNS configuration
- Tailscale DNS: enabled (device uses Tailscale DNS)
- Resolvers: 10.1.1.2, 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
- Split DNS routes: ts.net -> 199.247.155.53, 2620:111:8007::53
- Search domains: terrier-tegus.ts.net
- System DNS nameserver: 10.1.1.2

## Network health (netcheck)
- UDP: true
- IPv4: reachable; IPv6: not reachable (OS supports IPv6)
- Nearest DERP: Seattle (~2.9ms); next best: SFO 21.2ms, LAX 27.9ms, DEN 29.7ms, ORD 46.4ms, DFW 49.4ms
- Note: netcheck reported `portmap: monitor: gateway and self IP changed: gw=10.1.1.1 self=10.1.1.99`

## Tailnet devices (from `tailscale status`)
| Node                 | User    | OS      | Status                                             |
| -------------------- | ------- | ------- | -------------------------------------------------- |
| work-macbook-pro     | kyle@   | macOS   | online                                             |
| 22nd-apple-tv        | kyle@   | tvOS    | active; direct 10.1.1.248:41641, tx 14928 rx 22392 |
| adguard-pi           | kyle@   | linux   | idle; offers exit node                             |
| homeassistant-office | kyle@   | linux   | offline, last seen 9h ago                          |
| htpc                 | kyle@   | windows | offline, last seen 2d ago                          |
| kyle-iphone-17-pro   | kyle@   | iOS     | online                                             |
| kyle-macbook-pro     | kyle@   | macOS   | offline, last seen 2d ago                          |
| moss-apple-tv        | carmen@ | tvOS    | idle; offers exit node                             |
| surface-hub          | kyle@   | windows | offline, last seen 16d ago                         |
| surface-studio       | kyle@   | windows | offline, last seen 16d ago                         |
| truenas-scale-gw     | kyle@   | linux   | online                                             |

## Exit nodes
- Available: adguard-pi, moss-apple-tv (advertise exit node)
- Not using an exit node on this Mac
- `tailscale exit-node list` includes location-based Mullvad exit nodes (large list, not duplicated here)

## Services
- Serve: no config
- Funnel: no config
- App connector: not a connector

## Exit node + DNS troubleshooting
- Diagnostic script: `./scripts/tailscale-exitnode-dns-diag.sh <run-name>` writes `tmp/tailscale-exitnode-dns-diag-<run-name>.txt` for comparing exit nodes.
- With Mullvad exit nodes, ensure tailnet DNS resolvers use Tailscale IPs or MagicDNS names for your DNS server (not LAN-only IPs).
- If resolvers are LAN IPs (e.g., 10.1.1.2), either enable "Allow LAN access" when using the exit node or advertise/accept the LAN subnet route.
- Check the diag output for `tailscale dns status` (resolver list), `route -n get default` (default route via Tailscale), and resolver tests (ping/nc/dig).
- IPv6 resolver checks use `ping6` and `route -n get -inet6` on macOS.

## Related repo config
- `docker/tailscale-gw.yml` defines a separate TrueNAS gateway container (not this Mac).

## Refresh
Run `./scripts/tailscale-info.sh` to regenerate `tmp/tailscale-info.txt`, then update this file.
