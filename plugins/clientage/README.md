# clientage

The age of a Xymon client's last message, as the column `clientage` of its
host: green while it is younger than 15 minutes, yellow up to 30, red
beyond. A client whose launcher runs but whose `xymonclient.sh` hangs or
fails shows here before its columns go purple.

It is also the repository's example of a client part: see
[CONTRIBUTING.md](../../CONTRIBUTING.md), which part a piece goes in.

## Install

On a monitored host, as the owner of the client's `ext/`:

```sh
./xymon-plugin install --client clientage
./xymon-plugin enable --client clientage
```

On a Xymon server, into its own client tree, the server named:

```sh
XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --client clientage
XYMONHOME=/usr/lib/xymon/server ./xymon-plugin enable --client clientage
```

## How

Every 5 minutes its task reads the clock the Xymon client wrote in its last
message (`$XYMONTMP/msg.MACHINEDOTS.txt`, the `[clock]` section) and
compares it with `logfetch --clock` now. The thresholds are the two numbers
of its task's `CMD`, in `ext/clientage/tasks.cfg`, which an update keeps
as you edit it. Manual page: [clientage(8)](clientage.8).
