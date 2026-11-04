# interface

Monitors network interface speed, duplex, and link state using `ethtool`. Detects misconfigured or under-performing interfaces. Reports an `interface` column to the Xymon server.

The `--speed` option supports environments where the NIC is faster than the switch (e.g., a 10GbaseT NIC on a 1GbaseT switch): set it to the switch fabric speed so the negotiated rate is compared against what you actually expect.

## Requirements

- Python 3.x
- `ethtool` installed and the Xymon client user able to run it via `sudo`
- `ip` command available (iproute2)
- Standard Xymon client environment (`$XYMON`, `$XYMONSERVERS`, `$MACHINE`)

## Installation

```bash
cp interface.py $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/interface.py
cp interface.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

Grant the client user sudo access to `ethtool`, e.g. in `/etc/sudoers.d/xymon-ethtool`:

```
Cmnd_Alias ETHTOOL = /sbin/ethtool [0-9A-Za-z]*
xymon ALL = (root) NOPASSWD: ETHTOOL
```

## Usage

```
interface.py [--debug] [--speed MBPS] [--skip IFACE ...]
```

| Option | Description |
|---|---|
| `--debug` | Print the status message to stdout as well as sending it to Xymon |
| `--speed MBPS` | Expected link speed for every interface, in Mbps. Use when the NIC max > switch max |
| `--skip IFACE` | Interface to ignore; may be repeated. Adds to the built-in skip list (`lo`, `docker0`, `virbr0`) |

## Configuration (`interface.cfg`)

```
[interface]
    ENVFILE $XYMONCLIENTHOME/etc/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/interface.py --debug --speed 1000
    LOGFILE $XYMONCLIENTLOGS/interface.log
    INTERVAL 5m
```

Adjust `--speed` to match the switch fabric speed in your environment. Remove `--debug` in production to suppress stdout noise.

## Skipping interfaces

`lo`, `docker0` and `virbr0` are skipped by default. Add more with `--skip`, e.g. `--skip veth0 --skip br0`. Only interfaces backed by a real device (plus bond masters) are enumerated, so most virtual devices are ignored automatically.

## Status logic

| Condition | Color |
|---|---|
| Interface up, has IP, speed at expected rate | green |
| Interface up but no IP (and not a bond member) | yellow |
| Interface has IP but link is down | red |
| Interface down, no IP | clear |
| Speed below `--speed` (forced) | red |
| Speed below highest supported mode (no `--speed`) | yellow |

Bond masters are reported from `/proc/net/bonding/<iface>` (MII status); bond members are recognised via sysfs and are not flagged for lacking an IP.

## Origin

Original functionality was a Python 2 `iface` check by **netdar** (2013), circulated via [Andreas Dafert's blog](http://web.archive.org/web/20180328134523/http://blog.dafert.org/xymon-bigbrother-script-to-monitor-network-interfaces-duplex-settings-and-bonding/) (site now offline) and carried in [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks). That copy had **no license**, so this plugin is an **original, clean-room reimplementation** in Python 3: it reproduces the observable behaviour (the `interface` column, `--debug`/`--speed` options and colour logic) but shares no code with the original. netdar's script is credited as the design inspiration only.

## License

Copyright (C) 2026 xymon-monitoring contributors. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
