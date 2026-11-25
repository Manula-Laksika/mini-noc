# INC-00: Monitoring false alarm caused by firewall blocking Docker traffic

| Field | Value |
|---|---|
| Ticket ID | N/A (handled before osTicket was installed) |
| Priority / SLA | Normal / not applicable |
| Category | Network / Firewall |
| Status | Resolved |
| Affected | Uptime Kuma monitors: Server - SSH, Pi-hole - DNS, Pi-hole - Web UI |

## Timeline (approximate, from Uptime Kuma history and server logs)

| Event | Time |
|---|---|
| Monitors created in Uptime Kuma | ~13:00 |
| First failed checks (retrying) | ~13:01 |
| DOWN alerts: Server - SSH, Pi-hole - DNS | ~13:02 |
| Firewall drop logs reviewed | ~13:09 |
| nftables rules added and applied | ~13:10 |
| All monitors UP | ~13:10 |

**Time to resolve:** about 8 minutes from the first DOWN alert.

## Summary

The new monitoring tool reported that SSH and DNS on the home server were down, but both services were actually running fine. The server's firewall was blocking the monitoring tool's own checks. After allowing those specific checks through the firewall, the false alarms stopped.

## Impact

No real outage. SSH and DNS worked for all users. Only the monitoring dashboard showed incorrect DOWN status, which would have caused false alerts to the on-call engineer.

## Detection

Uptime Kuma showed Server - SSH and Pi-hole - DNS as DOWN (request timeout / `queryA ETIMEOUT`), and Pi-hole - Web UI as failing. Server - Ping, Router - Ping, Internet - Ping and Demo Web App stayed UP.

## Investigation

1. **Compared what failed and what worked.** Ping worked, so the host was up and the network path was fine. Failures were limited to TCP 22, UDP/TCP 53 and TCP 80 on the server itself.
2. **Noted that Demo Web App (port 8081) worked.** Docker-published ports take a different path through the firewall, so only checks against the host's own services were affected.
3. **Checked the firewall.** The `homefw` input chain accepts ports 22, 53 and 80 only when the packet arrives on interface `enp1s0` from `192.168.1.0/24`. Everything else hits `policy drop`.
4. **Checked the firewall drop log**, which showed the monitor's traffic being dropped:

```
sudo journalctl -k --since "15 min ago" | grep homefw-drop | tail -5

Nov 25 13:09:14 manula-lab kernel: homefw-drop: IN=br-0f2d6f74f5d1 OUT= SRC=172.18.0.2 DST=192.168.1.10 PROTO=TCP SPT=42628 DPT=80 SYN
Nov 25 13:09:26 manula-lab kernel: homefw-drop: IN=br-0f2d6f74f5d1 OUT= SRC=172.18.0.2 DST=192.168.1.10 PROTO=TCP SPT=42628 DPT=80 SYN
Nov 25 13:09:35 manula-lab kernel: homefw-drop: IN=br-0f2d6f74f5d1 OUT= SRC=172.18.0.2 DST=192.168.1.10 PROTO=TCP SPT=34824 DPT=22 SYN
Nov 25 13:09:55 manula-lab kernel: homefw-drop: IN=br-0f2d6f74f5d1 OUT= SRC=172.18.0.2 DST=192.168.1.10 PROTO=UDP SPT=60294 DPT=53
Nov 25 13:09:58 manula-lab kernel: homefw-drop: IN=br-0f2d6f74f5d1 OUT= SRC=172.18.0.2 DST=192.168.1.10 PROTO=UDP SPT=60294 DPT=53
```

(MAC addresses removed.) Every dropped packet came from the Docker bridge interface `br-0f2d6f74f5d1`, source `172.18.0.2` (the Uptime Kuma container), to ports 22, 53 and 80.

## Root cause

Uptime Kuma runs in a Docker container, so its checks arrive from the Docker bridge network (`br-*`, `172.18.0.0/16`), not from the LAN interface `enp1s0`. The firewall only allowed those ports from the LAN, so the container's traffic was dropped.

## Resolution

Added two narrow rules to the `input` chain in `/etc/nftables.conf`, before the final log rule. Only the ports the monitor needs are allowed, and only from Docker bridge subnets:

```
# Docker bridge networks (Uptime Kuma checks) - only the ports it monitors
iifname "br-*" ip saddr 172.16.0.0/12 tcp dport { 22, 53, 80 } accept
iifname "br-*" ip saddr 172.16.0.0/12 udp dport 53 accept
```

Applied with:

```
sudo cp /etc/nftables.conf /etc/nftables.conf.bak
sudo nft -c -f /etc/nftables.conf && echo "syntax OK"
sudo nft -f /etc/nftables.conf
```

The firewall file only recreates its own `homefw` table, so Docker's and Tailscale's rules were not affected.

## Verification

Within 1-2 minutes, Server - SSH, Pi-hole - DNS and Pi-hole - Web UI returned to UP in Uptime Kuma (Web UI showed `200 - OK`, DNS returned records for example.com).

## Prevention / follow-ups

- After any firewall change, check the monitoring dashboard for new DOWN alerts.
- Allow monitoring traffic with specific rules (interface, source, ports) rather than a broad accept.
- Keep the firewall config in version control (`configs/nftables.conf`) so changes are reviewable.
- Test new monitors against each service once before relying on their alerts.
- Lesson: ping and port checks can disagree. Comparing which checks fail and which pass quickly narrows the layer where the problem lives.

## Evidence

- Before: `screenshots/00-kuma-firewall-block.png` (SSH and DNS down)
- After: `screenshots/00-kuma-firewall-block-fix.png` (all monitors up)
- Firewall config: `configs/nftables.conf`
