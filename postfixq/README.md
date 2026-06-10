# postfixq

Monitors Postfix mail queue depth. Checks both the active queue (incoming + active + maildrop) and the deferred queue separately, alerting when either crosses configurable thresholds. Reports a `postfixq` column to the Xymon server.

## Requirements

- Perl 5
- `postconf` installed (`/usr/sbin/postconf`)
- `sudo` access for the Xymon client user to run `find` on queue directories (or loosen permissions)
- Standard Xymon client environment (`$XYMON`, `$XYMSRV`, `$MACHINE`, `$XYMONHOME`)

## Installation

```bash
cp postfixq.pl $XYMONCLIENTHOME/ext/
chmod +x $XYMONCLIENTHOME/ext/postfixq.pl
cp postfixq.cfg $XYMONCLIENTHOME/etc/clientlaunch.d/
```

## Usage

```
postfixq.pl YELLOW_THRESHOLD RED_THRESHOLD
```

Both thresholds are message counts for the **active queue**. The deferred queue threshold is automatically set to 10% of the active threshold.

## Configuration (`postfixq.cfg`)

```
[postfixq]
    ENVFILE /etc/xymon/xymonclient.cfg
    CMD $XYMONCLIENTHOME/ext/postfixq.pl 10 50
    LOGFILE $XYMONCLIENTHOME/logs/postfixq.log
    INTERVAL 5m
```

Adjust the two numeric arguments to match your expected mail volume.

## Threshold logic

| Queue | Yellow trigger | Red trigger |
|---|---|---|
| Active (incoming + active + maildrop) | ≥ `YELLOW_THRESHOLD` | ≥ `RED_THRESHOLD` |
| Deferred | ≥ 10% of `YELLOW_THRESHOLD` | ≥ 10% of `RED_THRESHOLD` |

## sudo configuration

Add to `/etc/sudoers` or a drop-in under `/etc/sudoers.d/`:

```
xymon ALL=(ALL) NOPASSWD: /bin/find /var/spool/postfix/*
```

## Status column

The Xymon column name is `postfixq`. Status reports both active and deferred counts and explains which threshold was crossed.

## Origin

Custom script from local plugins collection.
