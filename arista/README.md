# arista

Server-side Xymon monitor for Arista EOS switches. SSHs into each configured switch in user EXEC mode and reports 4 status columns per switch.

## Columns produced

| Column | What it shows |
|---|---|
| `cpu` | Load average + top EOS process CPU usage |
| `memory` | Physical memory used % with used/free MB |
| `hardware` | PSU status, fan status, temperatures — trusts Arista's own Ok/NotOk indicators |
| `net` | **Bandwidth**: uplink rate (Mbps) + 95th-percentile vs commitment<br>**Interfaces**: per-port status, flaps, error/CRC/drop counts; link-state log events at privilege 15<br>**Spanning tree**: port states, err-disabled detection, BPDU guard summary; STP log events at privilege 15 |

## Requirements

- Python 3 (stdlib only — no external packages)
- SSH access to each switch: user EXEC mode (no enable required)
- Privilege 15 for log access: `show logging | tail 200` requires privilege 15 on EOS. At lower privilege levels, the link event and STP event sections fall back to a `(privilege N — needs 15)` note.
- Network access from the monitoring host to each switch's management interface

## Installation

```bash
cp arista_monitor.py /usr/lib/xymon/server/ext/arista_monitor.py
chmod +x /usr/lib/xymon/server/ext/arista_monitor.py

mkdir -p /etc/xymon/conf.d
cp arista.cfg /etc/xymon/conf.d/arista.cfg
# edit arista.cfg: set XYMON_HOST, SSH_KEY, and add [switch] sections

mkdir -p /etc/xymon/ssh
ssh-keygen -t ed25519 -f /etc/xymon/ssh/id_rsa_arista -N ""
# distribute the public key to each switch
```

## SSH key setup on the switch

```
username xymon privilege 1 role network-operator ssh-key <pubkey>
```

For privilege 15 (to enable `show logging`):

```
username xymon privilege 15 role network-admin ssh-key <pubkey>
```

## Configuration (`arista.cfg`)

```ini
[DEFAULT]
XYMON_HOST         = xymon.example.com
XYMON_PORT         = 1984
SSH_USER           = admin
SSH_KEY            = /etc/xymon/ssh/id_rsa_arista

CPU_WARN           = 70
CPU_CRIT           = 85
MEM_WARN           = 80
MEM_CRIT           = 90
FLAP_WARN          = 1
FLAP_CRIT          = 5
IFACE_ERR_WARN     = 10
IFACE_ERR_CRIT     = 100
COMMITMENT_MBPS    = 1000
BW_WINDOW_HOURS    = 24

[arista1]
HOST               = arista1.example.com
XYMON_HOSTNAME     = arista1.example.com
UPLINK_PORTS       = Ethernet49/1 Ethernet50/1
COMMITMENT_MBPS    = 1000
# Ports to graph individually (creates ifstat.<port>.rrd via [ifstat] stanza):
# GRAPHED_PORTS      = Ethernet49/1 Ethernet50/1
# Ports whose flaps don't count toward column color (errors still do):
# FLAP_IGNORE_PORTS  = Ethernet43
# Ports fully silenced from column color (flaps + errors both suppressed):
# MUTED_PORTS        = Ethernet43
```

`XYMON_HOSTNAME` must match the hostname as registered in Xymon's `hosts.cfg`.

`UPLINK_PORTS` is a space-separated list of port names exactly as shown in `show interfaces` (e.g. `Ethernet49/1`). If omitted, the `net` column still sends green but shows no bandwidth data.

`GRAPHED_PORTS` (optional) is a space-separated list of port names to graph individually in Xymon. Each creates an `ifstat.<portname>.rrd` file picked up automatically by the `[ifstat]` "Network Traffic" stanza in `/etc/xymon/graphs.cfg`. No `graphs.cfg` changes needed. Port names with `/` are mapped to `-` in the filename (e.g. `Ethernet49/1` → `ifstat.Ethernet49-1.rrd`).

### Port alerting suppression

| Key | Effect |
|---|---|
| `FLAP_WARN` / `FLAP_CRIT` | New flap count per 5-min cycle that triggers yellow/red (global, default 1/5) |
| `FLAP_IGNORE_PORTS` | Space-separated ports whose flap count is excluded from column color. Errors on these ports still count. Port appears in the interface table annotated `[flap-ignored]`. |
| `MUTED_PORTS` | Space-separated ports fully silenced — flaps **and** errors suppressed from column color. Port still appears in the table annotated `[MUTED]`; active issues are listed in the Flagged section for visibility. |

Both `FLAP_IGNORE_PORTS` and `MUTED_PORTS` accept abbreviated EOS names (`Et43`) or long names (`Ethernet43`) interchangeably.

Use `MUTED_PORTS` for devices with predictable power-cycle or sleep/wake behavior (e.g. a Mac mini that sleeps overnight) where you want the activity visible in the column body but don't want the column to go yellow or red.

## Scheduling via `tasks.cfg`

```
[arista-monitor]
    INTERVAL 5m
    CMD /usr/bin/python3 /usr/lib/xymon/server/ext/arista_monitor.py
    LOGFILE /var/log/xymon/arista-monitor.log
```

Or via cron:

```cron
*/5 * * * * root /usr/bin/python3 /usr/lib/xymon/server/ext/arista_monitor.py >> /var/log/xymon/arista-monitor.log 2>&1
```

## RRD graphing

Uplink aggregate bandwidth is sent as a Xymon `data` message each poll cycle, populating `net.rrd` with DS fields `in`/`out` (bits/sec). Append the `[net]` stanza from `../graphs.cfg` to `/etc/xymon/graphs.cfg` to graph it.

Per-port bandwidth for ports listed in `GRAPHED_PORTS` is sent as `ifstat.<portname>.rrd` with DS fields `bytesReceived`/`bytesSent` (bytes/sec), which the existing `[ifstat]` "Network Traffic" stanza in `/etc/xymon/graphs.cfg` picks up automatically — no `graphs.cfg` changes needed.

## Bandwidth 95th percentile

Uplink bandwidth samples are stored in a SQLite database under `ARISTA_MONITOR_DATA_DIR` (default `/var/lib/xymon/arista-monitor/`), one `.db` file per switch. The `net` column shows the rolling 95th percentile over the configured `BW_WINDOW_HOURS` window (default 24 h, ~288 samples at 5-minute intervals). Until enough samples accumulate, the column shows an accumulating count and remains green.

## Port flap tracking

Arista's cumulative link-status-change counter is read each poll cycle and compared against the previous stored value to compute new flaps since the last poll. The delta drives the yellow/red threshold — one new flap = yellow, 5+ in a single cycle = red. Counters are stored in the same SQLite database as bandwidth samples and pruned after 7 days.

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ARISTA_MONITOR_CONF_DIR` | `/etc/xymon/conf.d` | Directory scanned for `*.cfg` files |
| `ARISTA_MONITOR_DATA_DIR` | `/var/lib/xymon/arista-monitor` | SQLite database directory |

## Origin

Custom plugin. Server-side script; runs on the monitoring host, not on the switch.
