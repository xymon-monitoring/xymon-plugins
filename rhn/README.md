# rhn

Monitors configuration-management drift between a host and a Red Hat Satellite 5.x / Spacewalk 2.x server. Uses `rhncfg-client verify` and `rhncfg-client diff` to detect files that have been modified locally relative to what the satellite expects. Reports an `rhn` column to the Xymon server.

## Requirements

- `rhncfg-client` installed and registered to a Satellite/Spacewalk server
- `sudo` access for the Xymon client user to run `rhncfg-client` (or configure sudoers)
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`)

## Installation

```bash
cp rhn.sh $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/rhn.sh
cp rhn.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

## Configuration (`rhn.cfg`)

```
[rhn]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/rhn.sh
    LOGFILE $XYMONCLIENTHOME/logs/rhn.log
    INTERVAL 15m
```

## How it works

1. Runs `sudo rhncfg-client verify` — lists files that differ from the satellite's managed configuration
2. If only one output line (the header), reports **green** — configuration is clean
3. If differences exist, runs `sudo rhncfg-client diff -d` and reports **red** with the full diff

## Status column

The Xymon column name is `rhn`. Status is **green** (no drift) or **red** (configuration differs from satellite).

## Notes

- Requires Satellite 5.x or Spacewalk 2.x — not compatible with RHSM/Insights
- The `sudo` wrapper is required because `rhncfg-client` needs root to read system-managed files

## Origin

From [`spiderr/xymon-checks`](https://github.com/spiderr/xymon-checks).

## License

Copyright (C) 2026 spiderr. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
