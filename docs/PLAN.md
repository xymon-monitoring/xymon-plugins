# Plan

What is still open, in one place. An item leaves this file when it is done;
one that is refused keeps a line with the reason. The issue or pull request
named holds the detail.

## Rules of work

- **Releases.** Plugins are installed and updated on the test machines only
  from release archives, never from a checkout. A release is tagged on
  `stable`, its draft checked (sha256, attestation, content) before it is
  published. A tag is pushed only when asked.
- **Tests before pushing** (here with `-j 16`; CI stays at `-j4`, its runners
  have 4 cores, and runs everything): the installer changed ->
  `tests/compat` and `plugins/xymon-plugin/tests`; a plugin changed -> its
  tests, those of the plugins whose `needs:` name it, and `tests/compat`;
  the SPEC changed -> `tests/compat/spec-rules.sh`. Measured: `-j 16` 74 s,
  `-j 32` 73 s (the longest tests, about 60 s, set the floor).
- **macOS before merging a change to the installer.** The compat suite runs
  on a Mac (bash 3.2 as `/bin/sh`, BSD userland): in a fresh `mktemp -d`,
  clone the branch and Xymon `main`, build Xymon with `./configure --server`
  (the CI's non-interactive variables, every path under the temp dir,
  `XYMONUSER=$(id -un)`, `HTTPDGID=_www`) and `make` -- never `make
  install`, no sudo, nothing outside the temp dir -- then `XYMON_SRC=<xymon>
  tests/run.sh -j <cores> tests/compat < /dev/null`. CI's `bash32-sh` only
  parses the scripts with bash 3.2 (`sh -n`).
- **Real trees.** A copy of a real Xymon tree for a test is made with `cp
  -RL`: Homebrew's `$XYMONHOME/ext` is a link to `/opt/homebrew/var/xymon/ext`,
  and `cp -RP` keeps it, so the copy writes into the real tree.

## The client part, next steps

`--client` installs, updates and removes a client part (#165); `status`,
`verify`, `outdated` and `clean` read a client's tree (#172, #181, #182); a
client part's task, `client-task:`, is a server part's in the client's
tree, `enable --client` linking it from `clientlaunch.d/`; xymon-plugin's
client task sends the client's `plugins` column, each client asking GitHub.

Next, in order (decided 2026-11-24, after two double analyses):

Task names by part (#190) and a server's own client tree (S36) are built.
Later, perhaps: an installation named by its top directory (`XYMONTOPDIR`,
holding `server/` and `client/`), as a shorthand for its server.

1. **One manual page per part** (below).
2. **`clientage`, an example plugin with all three parts**: the client
   part sends `clientage`, the age of the client's last message (green
   to 15 min, yellow to 30, red beyond); the server part one `clients`
   column on the server's host listing the clients behind; the tools part a
   `clientage` command through the API. To revisit before building, from
   the analyses: measure on the server with xymond's `clntstamp` (the time
   of the last client message received); list only hosts with client data;
   the tools part in Python over `xymonapi_client.py`, not shell and curl;
   the client part's age from the message's `[clock]` epoch, `stat` not
   being portable; its client part the first real one to try S36 with.
3. **xymon-plugin's column over the server and its client tree**, and
   `verify` and `outdated` with no part named covering that tree, as
   `status` does: the column's first line names the trees; `status` warns when a standalone
   client on the same machine sends under the server's host name. To ask:
   two `outdated` runs or one printing the client section, and how their
   exit codes combine.

Later for the client: each client asking its server for the latest
releases rather than GitHub (2026-11-24, with "the code comes from a
source" and #29); asking instead of refusing
a tree in doubt; the dialogue offering client trees; a client's
authentication (#29); `declared()` staging `client-files:` for `/plugins`;
an `ext/` owned but not writable (a raw `mkdir` error today).

## Under study: a plugin's pieces by role

Raised 2026-11-24 while designing `clientage`'s server part: the client
collects, the server processes, as Xymon does for its own columns. A
plugin would declare pieces by role rather than parts by place; each role
has one natural place in Xymon, which the installer would know, and the
place (client or server) follows from the role. Nothing is decided: to
analyse, with alternatives, before `clientage` (step 2) and the column
(step 3) go on. Both read in it: `clientage` collects `[clock]` (already
in the client message) and is analysed on the server from `clntstamp`;
updates are collected on each host (the versions in its tree, no network)
and analysed on the server (one GitHub query, colours for every host),
which is the "later" of #186's "GitHub first, the server later".

The roles, from Xymon's sources (`xymond/`, `xymond/etcfiles/`):

| role | Xymon's own | where a plugin's piece would go |
|---|---|---|
| collect, on the host | `xymonclient.sh`'s sections | a script in the client's `local/`: a `[local:NAME]` section of the client message |
| collect, from the server | `xymonnet`; `checks/` arista, ciscoasa | a server task polling the devices |
| collect, set by the server | `client-local.cfg` | its section in that file |
| transport | messages `client`, `status`, `data`, `notes`; xymond's channels `client`, `status`, `stachg`, `data`, `page`, `notes`, `enadis`, `clichg`, `user` | (Xymon's) |
| analyse: data to colour | `xymond_client`, `analysis.cfg` | a worker on the `client` channel (`xymond_channel`), its thresholds per host on the server |
| graph: storage | `xymond_rrd`, `rrddefinitions.cfg`, `TEST2RRD`, `NCV_*` | a setting in `xymonserver.d/` |
| graph: drawing | `showgraph`, `graphs.cfg` | a file in `graphs.d/` (read by the shipped `graphs.cfg`) |
| correlate | `combostatus`, `combo.cfg`; `depends`/`route` in `hosts.cfg` | a combination rule |
| alert | `xymond_alert`, `alerts.cfg`, `holidays.cfg` | rarely: the administrator's choice |
| history, raw data kept | `xymond_history`, `xymond_hostdata` | nothing: automatic |
| column documentation | `columndoc.csv` | its column's line |
| views, reports | `xymongen`, `critical.cfg`, `xymonmenu.cfg`; availability reports | rarely |
| use, outside Xymon | xymonapi, -mcp, -rag, -agent | the tools part, as today |

To settle: whether `PLUGIN` declares roles (`collect:`, `analyse:`,
`graph:`, `columndoc:` ...) in place of or beside `server-*`/`client-*`/
`tools-*`; how the installer places each (links from `ext/NAME`, as for
tasks); how a worker on a channel is started (a server task running
`xymond_channel`); what of #193 (clientage's client part sending its own
colour) stays. Refused on the way: `timediff`, which Xymon already covers
(`CLOCK` in `analysis.cfg` for a client against the server; the `ntp`
test of `xymonnet` for the server against NTP).

## Decided, to build

- **One manual page per part** (2026-11-23): tools in section 1 (their
  commands), the server `NAME.8`, the client `NAME-client.8`, each with SEE
  ALSO to the others; each part installs and removes its own page only.
  xymon-plugin's client page is a short one pointing to `xymon-plugin.8`.
  SPEC first: it changes S4 and S35, and xymon-plugin's `PLUGIN`, whose
  `client-manual:` names `xymon-plugin.8` today, as its server part does.
- **`ext/` as a full inventory** (2026-11-23): every entry is a plugin's
  install or listed as the site's own in a file the administrator writes
  (proposed `etc/xymon-plugin.d/local.cfg`, a name or simple pattern a
  line, read and never written by the installer); anything else is
  `untidy` in `verify`, with the advice to list it. install, update and
  remove touch neither. A client's tree alike. SPEC first: it changes S20,
  which says today that the rest of `ext/` is the site's and is not read,
  and S30. Until then only entries that look like a plugin's are read.
- **An alarm of five levels** -- RFC #113, version 2 (2026-11-18, after Stef
  Coene's reading): host, domain, test, instance, metric, in two stages --
  what the API can say on Xymon 4.3.31 (the renaming, the flags `stale`,
  `unreachable`, `suppressed` beside the last severity measured, a label,
  the instance where Xymon names it), and a state per instance as the
  direction of a Xymon 5.0.0. Asked, in order: the words, then the API
  before 5.0.0, then 5.0.0's goal. #114 stays a draft for reference.

## Decided in SPEC's Planned section, not yet built

Each becomes a numbered rule with the pull request that brings its test.

- **Removing the directory by hand removes everything of that part**: the
  settings in `ext/NAME/xymonserver.cfg`, seen through a link in
  `etc/xymonserver.d/`; what `/plugins` serves kept in `ext/NAME/`; and a
  virtualenv of each plugin's own in `ext/NAME/venv/`, in place of the one
  shared today. Tested by installing every plugin, enabling it, deleting
  `ext/`, and checking xymonlaunch, `xymoncmd`, `apachectl configtest`
  and `nginx -t`.
- **What `/plugins` serves can be checked against the repository**: a
  server serves the release archive it installed, not one built on the
  spot; `install` from a server not trusted with `--source` checks the
  archive by its attestation or by rebuilding it from the tag; a checkout
  that is no release tag has no attested archive and says so.
- **The parts asked for**: on a terminal, with no part named, the command
  asks which parts; `--server` and `--client` together, on a server, for
  its own client tree (S24 refuses two parts today).
- **`connect URL`**, **the code comes from a source** and **`trust`**, with
  the questions below.
- The checks under `checks/` move under `plugins/` as client parts when they
  get a `PLUGIN` file; a client part keeps its runtime files in
  `$XYMONTMP/NAME` and its logs in `XYMONCLIENTLOGS`.

## Waiting on an answer

- **The code comes from a source**: `install` and `update` taking a
  plugin's code from the Xymon server, GitHub releases or `--source`;
  whether the checkout accepted with `y` counts as named, so trusted.
- **`connect`** (one token, hooks, menu): where a ticked plugin not
  installed comes from; `connect` given a URL on a server; a second
  `connect:`. `--tools` and `connect --tools` proposing the installation
  (decision 55) come with it.
- **`trust`** and its four guards: how each is turned off; the command that
  sets `trust` and the emergency stop; the block list's form; the setting by
  which a server allows serving an archive no proof checks.
- The others of SPEC's "Open, to decide": where the search index lies on a
  server (`$XDG_CACHE_HOME/xymonapi-rag/` or under `$XYMONVAR`); how much of
  "while it runs" a test can check; `install --all` and a plugin needed when
  some are installed, and S3 and S8 part by part; for a server's own client,
  which tree's `xymon-plugin.cfg` keeps its source; whether a standalone
  client's server URL is given only by `connect --client`; who owns the
  files written for `SUDO_USER` under `sudo`.

## Later

- **Going back to an earlier version**: today by hand only (the older
  release's archive, then `update` from it), with no warning that it goes
  down. With "the code comes from a source": `install`/`update --version
  X.Y.Z` (attestation checked), "go back to the previous version" in the
  dialogue, any downgrade said, `[y/N]` on a terminal, `--force` off one.
  The warning alone can come first. Until then every change keeps the
  manual way working: an older archive's `update` installs it, recognises
  the newer version's unedited files and keeps the edited ones.
- **Two concurrent runs by two users** on one plugin are caught only by the
  set-aside directory's owner check: a lock.
- **`verify` of the `/plugins` stage depends on the tree's place**: a copy
  of a tree at another path reports every staged file as not what was
  staged, though the files are identical. Find why; a moved tree would see
  the same.
- **A server tree whose `ext/` is a link** (Homebrew): no test builds one.
- `plugin-resume.sh` (54 s): keep the cuts that matter, one by signal; the
  full cut matrix stays a tool to run by hand before a release.
- The dialogue `eval`s a printed command (quoted by `hx`; `set --` would be
  safer); `xymon_trees` splits fields on spaces, so a tree path with one is
  not detected; a `MANDIR` changed between install and remove leaves the
  old manual link (MANIFEST records it, unused); an installed `PLUGIN` with
  malformed needs makes every removal stop in `needed`/`depth`.
- Plugin manual pages: facts the shortened READMEs kept (xymonapi's family
  table, the language model section, Apache/lighttpd minimums,
  `XYMONAPI_LISTEN`, removal keeping the token files) are candidates for the
  manual pages.
- After an update, optionally: wait for `/health`'s version; `update --auto`
  with #135's safeguards (#161); xymon#505's two additions.
- The prose credit warning of xymon#863: copy its `::warning` step into
  `.github/workflows/attribution.yml`.
- `xymon-setup`, a tool of its own to install Xymon itself (server or
  client, from packages, Homebrew or a build), then calling `xymon-plugin`.
  Nothing to prepare now.
- **A review by another provider** of what only Claude read: the API's
  `MANIFEST` watch (`app.py`) and the `plugins` column
  (`xymon-plugin-report.sh`), unchanged since #151-#160.

## Waiting on others

- **Xymon**: #128 tracks what the plugins wait for (#911, #920, #921, #160,
  4.3.32) and the Homebrew tap (#44, #47); `expect.warn`/`reject.warn`
  (xymon#505), `interval=` (xymon#932), holidays outside alerts (xymon#933),
  KILLGROUP (xymon#960), NEEDS after the whole configuration (xymon#961).
- **Stef's pull requests** #45 (`/pages`) and #33 (`/graphs` through
  `showgraph.cgi`): one review each, kept up to date.
- **Debian's runtime directory** -- xymon#160 sets `XYMONRUNDIR=/run/xymon`,
  which makes the relay work on Ubuntu with nothing to set (#53, #67).
- **checks/interface in Python** -- #3, awaiting a decision.

## Open questions

- **The side a plugin is installed for** -- #39: what an install records;
  whether a server's tree is running (`xymonlaunch`); a client's
  `XYMONSERVERS` and `CLIENTHOSTNAME`; on a client, `XYMONTMP` in place of
  `XYMONRUNDIR` for runtime files.
- **Debian and Ubuntu's packaged Xymon and Python** -- #47: the stable
  archives ship Xymon 4.3.30, below the floor; xymon-apt backports 4.3.31.
- **The Xymon floor** -- #68: revisit 4.3.31 once 4.3.32 is released.
- **API first** -- #51: the contract stays, the implementation is
  replaceable; whether `/graphs` stays a PNG.
- **A repository plugin** -- #29.

## Known limits, left for now

- The relay check reads owner and mode bits, not ACLs (#53).
- The SELinux module (#69) lets the web server connect to every Xymon
  daemon's sockets once its boolean is on. A Xymon built from source on RHEL
  has no `/run/xymon` label unless the admin gives it.
- The local socket's path is checked only together with the relay's (#53).
- `cfgval`, the fallback when `xymoncmd` cannot be run, reads one level of
  `xymonserver.d/` (marked `ponytail:` in the installer).

## Refused

- **A server's client tree's ext/ held to the server's ext/ owner, or
  root**: RPM gives client/ext to xymon and the server's tree to root, so
  it was refused with a chown against the package, and root accepted let a
  link to any root's directory pass (2026-11-24); held to the owner of the
  server's tasks.d/ instead, where the task's link is written.
- **Comparing task links through any spelling of the tree** (a link to it):
  a relative target was resolved against the current directory, not the
  link's, and it served only a respelling of XYMONCLIENTHOME no install
  makes (2026-11-24); a respelling shows in verify: disable, then enable.
- **CI running only the tests a change touches**: a test would not run on
  every lane (2026-11-21); CI went from about 7 to 2 minutes with every test
  on every lane.
- **A macOS job running the suite in CI**: the suite runs on a Mac by hand
  before merging a change to the installer (2026-11-23).
- **Requiring Xymon 4.3.32 now**: not released; it would leave out every
  released Xymon and would not fix the Ubuntu case (#68).
- **Python as a plugin `needs:`**: a system requirement, not a directory
  the installer installs.
- **A Linux abstract socket, `SO_PEERCRED`, or TLS on the relay socket**:
  Linux only, no common web server syntax, credentials sent before the API
  takes part, or lighttpd cannot proxy to HTTPS.
- **Falling back to `$XYMONHOME/tmp` where `XYMONRUNDIR` is empty**: against
  S22, which follows Xymon's own fallback.
- **Grouping `xymonapi-rag.sh`'s model loads**: 0.5 s each, measured (#62).
- **`MANIFEST` in what makes a directory an install**: an update cut short,
  by pip or a signal, must be resumable by `update` (2026-11-23).
- **Guessing "cut short" from a missing `VERSION`**: an explicit in-progress
  marker decides it (2026-11-23).
