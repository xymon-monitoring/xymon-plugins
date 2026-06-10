# interface

Monitors network interface speed, duplex, and link state using `ethtool`. Detects misconfigured or under-performing interfaces. Reports an `interface` column to the Xymon server.

Forked from [Dafert's iface check](https://blog.dafert.org/xymon-bigbrother-script-to-monitor-network-interfaces-duplex-settings-and-bonding/) with the addition of a `--speed` option for environments where the NIC is faster than the switch (e.g., 10GbaseT NIC on a 1GbaseT switch).

## Requirements

- Python 2.x (**note:** uses `print` statement and `has_key()` — needs Python 2 or modernisation for Python 3)
- `ethtool` installed and the Xymon client user able to run it via `sudo`
- `ip` command available
- Standard Xymon client environment (`$XYMON`, `$XYMONSERVERS`, `$MACHINE`)

## Installation

```bash
cp interface.py $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/interface.py
cp interface.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

## Usage

```
interface.py [--debug] [--speed N]
```

| Option | Description |
|---|---|
| `--debug` | Print all output to stdout and send to Xymon |
| `--speed N` | Override expected speed for all interfaces (Mbps). Use when NIC max > switch max |

## Configuration (`interface.cfg`)

```
[interface]
    ENVFILE $XYMONCLIENTHOME/etc/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/interface.py --debug --speed 1000
    LOGFILE $XYMONCLIENTLOGS/interface.log
    INTERVAL 5m
```

Adjust `--speed` to match the switch fabric speed in your environment. Remove `--debug` in production to suppress stdout noise.

## Blacklisting interfaces

Edit the `BLACKLIST` variable near the top of `interface.py`. Append `interfacename:` for each interface to skip:

```python
BLACKLIST="lo:virbr0:docker0:"
```

## Status logic

| Condition | Color |
|---|---|
| Interface up, has IP, speed at expected rate | green |
| Interface up but no IP (and not a bond member) | yellow |
| Interface has IP but link is down | red |
| Interface down, no IP | clear |
| Speed below `--speed` or below highest supported mode | yellow/red |

Bond interfaces are checked via `/proc/net/bonding/<iface>` for MII status.

## Origin

From [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks), originally by netdar (2013).
