# openmanage

Monitors Dell server chassis health via Dell OpenManage using `omreport chassis`. Checks fans, intrusion, memory, power supplies, temperatures, voltages, hardware log, and batteries. Reports an `openmanage` column to the Xymon server.

Original script by Brian Smith-Sweeney. Version 0.56 (local patched).

## Changes in v0.56 (local patch over upstream v0.55)

- `grep -A30` instead of `-A9` — captures components beyond position 9 (e.g., Batteries on servers with many sensors)
- Added `Batteries` case to drill-down loop (`omreport chassis batteries`)
- Silenced grep with `-q` flag in color-detection `if/elif` to suppress spurious output

## Requirements

- Dell OpenManage Server Administrator installed; `omreport` on `PATH` under `/opt/dell/srvadmin/bin/`
- bash
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`, `$XYMONHOME`, `$XYMONTMP`)

## Installation

```bash
cp openmanage.sh $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/openmanage.sh
```

Add to `$XYMONCLIENTHOME/etc/clientlaunch.cfg` or drop a file in `clientlaunch.d/`:

```
[openmanage]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/openmanage.sh
    LOGFILE $XYMONCLIENTHOME/logs/openmanage.log
    INTERVAL 60s
```

## How it works

1. Runs `omreport chassis` and extracts the severity column
2. Determines overall colour from the worst severity found
3. For each failed component, runs the corresponding level-3 `omreport chassis <component>` command and appends the output
4. Sends the full report to Xymon including a link to the OpenManage web interface

## Status colour logic

| OMSA severity | Xymon colour |
|---|---|
| All Ok | green |
| Any Non-Critical | yellow |
| Any Critical | red |
| Unrecognised state | purple |

## Known limitation

OMSA messages can exceed Xymon's message size limit. If multiple components fail simultaneously you may see `DATA TRUNCATED` in the column. This is a known upstream limitation.

## Status column

The Xymon column name is `openmanage`.

## Origin

From [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext) (v0.55), patched locally to v0.56. Original by Brian Smith-Sweeney, University of California (2002). See script header for full license.
