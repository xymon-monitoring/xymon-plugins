# omsa-raid

Monitors Dell PowerEdge RAID controllers via Dell OpenManage Server Administrator (OMSA). Uses `omreport` to check controller state, virtual disk health, physical disk health, and battery backup unit status. Reports a `raid` column to the Xymon server.

Original script by Ben Argyle, University of Cambridge. Version 2.2.

## Supported controllers

Tested with Dell PERC2 through PERC6, H700, and CERC ATA/SATA cards, under OMSA versions 3.3 through 6.5.

## Requirements

- Dell OpenManage Server Administrator (OMSA) installed; `omreport` at `/opt/dell/srvadmin/bin/omreport`
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`, `$XYMONHOME`, `$XYMONTMP`)
- bash with support for C-style `for` loops

## Installation

```bash
cp omsa-raid.sh $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/omsa-raid.sh
```

Add to `$XYMONCLIENTHOME/etc/clientlaunch.cfg` or drop a file in `clientlaunch.d/`:

```
[omsa-raid]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/omsa-raid.sh
    LOGFILE $XYMONCLIENTHOME/logs/omsa-raid.log
    INTERVAL 5m
```

## How it works

For each RAID controller found by `omreport storage controller`:

1. Checks controller status and firmware version
2. Checks battery backup unit (if present)
3. Enumerates virtual disks and their member array disks
4. Colours each item green/yellow/red based on OMSA state strings

Overall column colour is the worst colour seen across all controllers.

## Status colour logic

| OMSA state | Xymon colour |
|---|---|
| Ok / Ready | green |
| Non-Critical / Degraded / Charging / Reconditioning | yellow |
| Anything else | red |
| No battery present | clear |

**Note:** `Non-Critical` physical disks are marked **green** because OMSA flags all non-Dell-branded disks as Non-Critical regardless of health.

## Status column

The Xymon column name is `hardware`.

## Origin

From [`spiderr/xymon-ext`](https://github.com/spiderr/xymon-ext). Original v1.0–v2.2 by Ben Argyle (bda20@cam.ac.uk / ben@lspace.org), University of Cambridge. Public domain.

## License

Public domain. Original by Ben Argyle (bda20@cam.ac.uk), University of Cambridge.
