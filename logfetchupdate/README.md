# logfetchupdate

Downloads an updated `logfetch` configuration file from the Xymon server and writes it to the client's temp directory. The `logfetch` client daemon then picks up this file automatically, allowing centralised management of log monitoring rules from the server side.

**Requires Terabithia Xymon RPMs > 4.3.18** on the server for the `clientconfig` protocol command.

## Requirements

- Xymon client installed with `$XYMON`, `$XYMSRV`, `$MACHINE`, `$MACHINEDOTS`, `$XYMONTMP` set
- Terabithia patched Xymon server > 4.3.18
- Either `STATUSMODE=yes` or `SUBMITMODE=yes` in the client environment

## Installation

```bash
cp logfetchupdate $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/logfetchupdate
```

Add to `$XYMONCLIENTHOME/etc/clientlaunch.cfg` or drop a file in `clientlaunch.d/`:

```
[logfetchupdate]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/logfetchupdate
    LOGFILE $XYMONCLIENTHOME/logs/logfetchupdate.log
    INTERVAL 5m
```

## Environment variables

| Variable | Description |
|---|---|
| `STATUSMODE` | Set to `yes` to enable this script |
| `SUBMITMODE` | Alternative to `STATUSMODE` |
| `XYMCONFIGSRV` | Override `XYMSRV` to fetch config from a specific server |
| `CONFIGCLASS` | Config class string passed to `clientconfig` request |
| `SERVEROSTYPE` | OS type string passed to `clientconfig` request |

## How it works

1. Exits silently if neither `STATUSMODE` nor `SUBMITMODE` is `yes`
2. Sends a `clientconfig $MACHINE.$SERVEROSTYPE $CONFIGCLASS` message to the Xymon server
3. If a non-empty response is received, atomically replaces `$XYMONTMP/logfetch.$MACHINEDOTS.cfg`
4. `logfetch` picks up the updated config on its next run

## Origin

Custom script; requires Terabithia Xymon server patches. Not available in upstream Xymon.

## License

Copyright (C) 2026 spiderr. GNU General Public License v2 or later — see <https://www.gnu.org/licenses/>.
