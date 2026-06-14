# ciscoasa

Server-side Xymon monitor for Cisco ASA firewalls. SSHs into each configured ASA, collects health and performance data, and sends status columns and RRD bandwidth data directly to the Xymon daemon via TCP. Stores bandwidth samples in a local SQLite database for 95th-percentile calculations.

## Xymon columns produced (per firewall)

| Column | What it shows |
|---|---|
| `cpu` | 5-sec / 1-min / 5-min CPU % + top processes by CPU |
| `memory` | Memory used % with used/free MB |
| `conn` | Active connection count + NAT translation table count |
| `hardware` | Physical health: PSU status, fan status, temperatures — trusts ASA's own OK/FAIL indicators |
| `net` | Bandwidth (current rate + 95th-percentile vs commitment) and per-interface error/drop/reset counters |
| `vpn` | IKEv2 tunnel count and state — **only sent if VPN is configured**; column is suppressed entirely on firewalls with no IKEv2 SA |

## Requirements

- Python 3
- `pexpect` — `pip3 install pexpect`
- SSH key access to each ASA's admin account (RSA key, SHA-1 host key compatibility required for ASA 9.14)
- Network access from the monitoring host to each ASA's management interface
- Write access to the SQLite data directory (`/var/lib/xymon/asa-monitor/` by default)

## Installation

```bash
cp asa_monitor.py /usr/lib/xymon/server/ext/asa_monitor.py
chmod +x /usr/lib/xymon/server/ext/asa_monitor.py

# Install config
mkdir -p /etc/xymon/conf.d
cp ciscoasa.cfg /etc/xymon/conf.d/ciscoasa.cfg
chmod 600 /etc/xymon/conf.d/ciscoasa.cfg   # contains credentials
```

## Configuration (`ciscoasa.cfg`)

The config file uses Python `configparser` format. `[DEFAULT]` values apply to all firewalls; per-firewall `[section]` overrides them.

```ini
[DEFAULT]
XYMON_HOST         = xymon.example.com
XYMON_PORT         = 1984
SSH_USER           = admin
SSH_KEY            = /etc/xymon/ssh/id_rsa_asa
ENABLE_PASSWORD    = <your-enable-password>
CPU_WARN           = 70
CPU_CRIT           = 85
MEM_WARN           = 80
MEM_CRIT           = 90
CONN_WARN          = 50000
CONN_CRIT          = 80000
XLATE_WARN         = 50000
XLATE_CRIT         = 80000
COMMITMENT_MBPS    = 100
BW_WINDOW_HOURS    = 24
IFACE_ERR_WARN     = 10
IFACE_ERR_CRIT     = 100

[asa1]
HOST               = asa1.example.com
XYMON_HOSTNAME     = asa1.example.com
OUTSIDE_IFACE      = outside
MONITOR_IFACES     = outside inside
COMMITMENT_MBPS    = 100
# Interface nameifs to graph individually (creates ifstat.<nameif>.rrd):
# GRAPHED_PORTS      = outside inside
```

Add a new `[section]` block for each additional ASA. The section name is the firewall's short name used on the command line.

### Key settings

| Setting | Description |
|---|---|
| `HOST` | Firewall management hostname/IP |
| `XYMON_HOSTNAME` | Hostname as registered in Xymon (used in status messages) |
| `OUTSIDE_IFACE` | `nameif` of the internet-facing interface (for bandwidth tracking) |
| `MONITOR_IFACES` | Space-separated list of `nameif` names to check for errors |
| `COMMITMENT_MBPS` | 95th-pct bandwidth alert threshold (yellow at 85%, red at 100%) |
| `BW_WINDOW_HOURS` | Rolling window for 95th-pct calculation (default 24h = 288 samples) |
| `GRAPHED_PORTS` | Space-separated list of `nameif` names to graph individually via the `[ifstat]` "Network Traffic" stanza; each creates `ifstat.<nameif>.rrd` (no `graphs.cfg` changes needed) |

## Running

```bash
# Poll all configured firewalls
python3 /usr/lib/xymon/server/ext/asa_monitor.py

# Poll one firewall by short name
python3 /usr/lib/xymon/server/ext/asa_monitor.py asa1
```

## Scheduling via cron

Run every 5 minutes so bandwidth samples stay on the expected interval and `status+600` messages don't expire between polls:

```cron
*/5 * * * * root /usr/bin/python3 /usr/lib/xymon/server/ext/asa_monitor.py >> /var/log/xymon/asa_monitor.log 2>&1
```

Or add to `/etc/xymon/tasks.cfg`:

```
[asa-monitor]
    INTERVAL 5m
    CMD /usr/bin/python3 /usr/lib/xymon/server/ext/asa_monitor.py
    LOGFILE /var/log/xymon/asa_monitor.log
```

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `ASA_MONITOR_CONF_DIR` | `/etc/xymon/conf.d` | Directory scanned for `*.cfg` files |
| `ASA_MONITOR_DATA_DIR` | `/var/lib/xymon/asa-monitor` | SQLite bandwidth database directory |

## Bandwidth 95th percentile

Each run stores a `(timestamp, in_bps, out_bps)` sample in a per-firewall SQLite database. The 95th percentile is computed in pure Python over the configured window (default 24 h). Data older than 30 days is pruned automatically. The column shows **accumulating** until enough samples are collected.

A Xymon `data` message is sent each run so bandwidth is also stored in `net.rrd` for native Xymon RRD graphing.

## Notes

- ASA 9.14 only offers SHA-1 RSA host keys; `HostKeyAlgorithms=+ssh-rsa` is set automatically in SSH options
- `StrictHostKeyChecking=no` is set — ensure SSH key fingerprints are validated manually on first use
- If SSH or data collection fails, all columns for that firewall are set **purple** with the error reason
- The config file contains credentials — set permissions to `600` and owner to the user running the script

## Origin

Custom script. Server-side poller; runs on the Xymon server, not on the monitored ASA.

## License

Copyright (C) 2026 spiderr. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
