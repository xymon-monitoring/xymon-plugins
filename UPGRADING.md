# Upgrading

What a change that breaks something asks of you, newest first: the plugin,
its version, what breaks, and what to do. Every other change needs nothing
but installing the new code (see each plugin's README). CI refuses a change
that breaks the API's contract without a line here.

## A task's link becomes tasks.d/NAME.cfg, from November 2026

A plugin's task is on when `etc/tasks.d/NAME.cfg` links to its task file;
the link was `tasks.d/NAME`. A packaged Xymon may read only the files of
`tasks.d/` that end in `.cfg`, where Xymon's own reads them all. The next
`./xymon-plugin update --server`, or `enable`, renames the link an older
install made, and the task stays on: nothing to do. What breaks: a script
that names `tasks.d/xymonapi`. Also: `enable` now refuses a server whose
`tasks.cfg` has no `directory` line for `tasks.d/`, and says the line to
add; `--force` makes the link where the server reads it another way.

## /alarms says clear and blue as the standards do, from xymonapi 8.0.0

`/alarms` gave a test with no data (clear) and one disabled (blue) the
severity `minor`, as a warning, and the status `firing`. They now have
the severity `indeterminate`, ITU-T X.733's word for a state that cannot
be told, and a disabled one the status `suppressed`, as Alertmanager lists
a silenced alert: both stay listed. `Severity` gains `indeterminate` and
`Alarm.status` `suppressed`. What to do: a client that counts alarms by
severity, or takes every one for firing, reads these values; one that
wants what needs acting on passes over `indeterminate` and `suppressed`.

## /health says each version under what it is the version of, from xymonapi 7.0.0

`/health` gave `version`, the API's, and `server_version`, xymond's answer
to a ping, with `alive` for whether xymond answered: names that did not say
whose, and `version` in two forms, `6.0.1` or `xymonapi/v6.0.1`. It now
gives `api.version`, always `X.Y.Z`, and `xymond.alive`, `xymond.version`
(`4.3.32-dev`) and `xymond.answer` (`xymond 4.3.32-dev`); `version`,
`server_version` and the top-level `alive` are gone. What to do: a script
reading `/health` reads the new fields; update the server and every
machine's tools together (`./xymon-plugin update --server`, then
`--tools`): a client of this version reads no version from an older API,
and says no difference of versions with it.

## The client's directory becomes ~/.config/xymonapi, from xymonapi 6.0.0

`xymonapi-connect` keeps the API's URL, its token and a certificate in
`$XDG_CONFIG_HOME/xymonapi/`, the plugin's own name (SPEC, S28); it was
`xymon-api/`, which is read no more. What to do: move the directory,
`mv ~/.config/xymon-api ~/.config/xymonapi`, or run `xymonapi-connect URL`
again, which asks your password once. An AI tool registered with
`XYMONAPI_TOKEN_FILE` or `XYMONAPI_CA` under the old directory needs them
renamed too, or `xymonapi-mcp register URL` again.

## install.sh becomes xymon-plugin, from November 2026

The installer is `./xymon-plugin`, with a verb and the part it acts on:
`install-server NAME` is `install --server NAME`, `install-tools` is
`install --tools`, `uninstall-*` is `remove`, and so for `enable`,
`disable` and `status`; `venv-server` and `venv-tools` are `update --venv`,
the virtualenv having no verb of its own; `install.sh` is gone, and each old action
is refused, naming the new form. What breaks: a script that calls
`install.sh`. Also: `install` and `remove` need a plugin named, or `--all`;
`install` refuses a plugin installed already, which `update` replaces; a
script names the part, `--server` or `--tools`; and the tools are refused
as root unless `PREFIX` or `DESTDIR` is given; off a terminal, modules are
fetched only with `--venv`; `enable` refuses a plugin whose Python lacks
its modules. What is installed, and where, is unchanged. A plugin
installed before reads as needing nothing, as its copy of `PLUGIN` has
`needs:`, not `server-needs:` or `tools-needs:`: `remove --all` then
removes in no set order, which is harmless when all go; to remove one
alone, update first.

## xymonapi-connect asks the password once more, from xymonapi 5.0.2

`xymonapi-connect` now keeps the API's URL beside the token, in
`~/.config/xymon-api/NAME.url`, and sends a token only to that URL. What
breaks: on a machine connected before, the first `xymonapi-connect URL`, or
`xymonapi-mcp register URL`, asks your password again, once, and keeps a new
token, which replaces the one before on that server; a token kept for
another server stays valid there until its `/tokens` revokes it.
The same server reached by another URL asks it too. Then the agent and
`xymonapi-rag` find the API with no `XYMONAPI_URL` set.

## The relay socket moves to Xymon's runtime directory, from xymonapi 5.0.0

The web server's relay socket is now `$XYMONRUNDIR/xymonapi/relay.sock`,
in the directory Xymon keeps for its sockets, or in its log directory,
`$XYMONSERVERLOGS`, when `XYMONRUNDIR` is empty, as Xymon does. It was
`$XYMONHOME/tmp/xymonapi-relay/relay.sock`. The socket for the server's
own programs is beside it, `$XYMONRUNDIR/xymonapi/local/api.sock`; it was
`$XYMONVAR/xymonapi/api.sock`, and the clients look only at the new path.
The install reads the directory
from `$XYMONHOME/etc/xymonserver.cfg` and replaces a 4.0.0 snippet it finds
unedited. What breaks: a snippet you edited is kept, and the install says
it differs: put the new socket path in it. Where `XYMONRUNDIR` names a
variable the install cannot read, the snippets keep `@XYMONRUNDIR@`, and
the install says to put the directory there. An SSH tunnel goes to the new
path. Setting `XYMONAPI_RELAY_SOCKET` keeps the socket where you name it.

## The web server reaches the API on its relay socket, from xymonapi 4.0.0

The API now also answers on a Unix socket for the web server,
`$XYMONHOME/tmp/xymonapi-relay/relay.sock` (`XYMONAPI_RELAY_SOCKET`), in plain
HTTP whether port 1986 speaks HTTPS or not, asking the same password or
token; the web server's snippets pass `/xymon/api/` there. Before, they
passed it to `127.0.0.1:1986` in plain HTTP, which failed with a 502 where
1986 speaks HTTPS, as it does by itself once xymond's certificate is in
`etc/tls/`. An install replaces a snippet it finds as an older version
shipped it; one you edited is kept, and the install says it differs: put the new
`ProxyPass`, `proxy_pass` or `proxy.server` line in it, from the snippet
the plugin ships. The snippets need Apache 2.4.7, or lighttpd
1.4.36, or later. An SSH tunnel can go to the socket too:
`ssh -L 1986:$XYMONHOME/tmp/xymonapi-relay/relay.sock HOST`.

What breaks: a path with a trailing slash, which redirected to the one
without, is now not_found -- a redirect would send a client behind a web
server back to http://. And there is no relay where the socket's
directory, or one on the way to it, can be changed by anyone but root and
the Xymon user: the API runs on, says why in its log, and `/health` says
`"relay": "refused"`; the log names the directory, and the group that may
write it. On Homebrew, `/opt/homebrew`'s directories -- `opt`, `Cellar`,
`var` -- are writable by the `admin` group, by Homebrew's design: set
`XYMONAPI_RELAY_TRUSTED_GROUPS=admin` in `xymonserver.d/`, if every admin is
trusted with the API's passwords.
`XYMONAPI_RELAY_SOCKET` set empty turns the relay off.
Under SELinux, as with Xymon's RPM on RHEL, Apache must be allowed to
connect to the socket: from xymonapi 5.0.1 the install loads a module
for it, its boolean off, `setsebool -P xymonapi_relay on`.

## Every install action names its side, install.sh from November 2026

`./install.sh install`, `uninstall`, `venv`, `enable`, `disable` and
`status`, the server actions without `-server`, are refused, naming the
action with a side: `install-server`, `uninstall-server`, `venv-server`,
`enable-server`, `disable-server`, `status-server`, and for the first
three and `status` the `-tools` ones too. A script that used a short
spelling adds `-server`. Nothing installed changes. The plain verbs are
`xymon-plugin`'s, the command SPEC.md plans to replace `install.sh`.

## The server actions need a Xymon server's tree, install.sh from November 2026

Every server action -- `install-server`, `enable-server`,
`disable-server`, `status-server`, `uninstall-server`, `venv-server` --
now reads the tree `XYMONHOME` names for a server's two marks,
`etc/xymonserver.cfg` and `bin/xymond`, and refuses it before changing
anything when they are not both there: a client's tree, part of a pair, or
a directory that is no Xymon tree at all. An install into an empty
directory, which used to make one, is refused; to stage the plugins for a
package, set `DESTDIR`, under which no marks are read. A plugin left in a
tree whose Xymon is already gone is removed by deleting `ext/NAME`. A real
server, packaged or built from source, needs nothing.

## A password file is needed, from xymonapi 3.0.0

With `XYMONAPI_PASSWD` not set and no `$XYMONHOME/etc/xymonpasswd`, the API
answered anyone who reached it. It now does not start, and says why. A
missing file -- a configuration kept from an older install that does not
read `xymonserver.d/`, a new install without the web pages' passwords --
no longer opens the API without a word. Create the file with `htpasswd`,
name another in `XYMONAPI_PASSWD`, or, for an API open to anyone who
reaches it, set `XYMONAPI_PASSWD=""` in a file under `xymonserver.d/`.

## Server tasks on and off, by a link, from xymonapi 2.4.0

A plugin's task is no longer turned on by removing `DISABLED` from its
file: it is on when `etc/tasks.d/NAME` links to `ext/NAME/tasks.cfg`, which
`XYMONHOME=... ./xymon-plugin enable --server NAME` makes and `disable-server
NAME` removes. The first install with this version keeps each task as it
was: one still `DISABLED` stays off and loses that line, and says how to
turn it on; one you enabled stays on. A script that enabled a task by
editing its file runs `enable-server` instead.

## The install actions, from xymonapi 2.3.0

`./install.sh install-client`, `uninstall-client` and `venv-client` are now
`install-tools`, `uninstall-tools` and `venv-tools`: what they install are
the plugins' commands, on your own machine, and "client" is Xymon's word for
a monitored host. The old names are refused, saying the new one. The server
actions gain `-server` -- `install-server`, `uninstall-server`,
`venv-server` -- and keep their old spellings. What is installed, and where,
is unchanged: an install over the old one needs nothing more. In a
`PLUGIN` file, `client-files`, `client-manual`, `client-modules` and
`uninstalled-client` are `tools-files`, `tools-manual`, `tools-modules` and
`uninstalled-tools`. The directory the server stages the plugins in for
`/plugins`, `ext/xymon-plugins-client`, is `ext/xymon-plugins-dist`; a
server install renames nothing, so remove the old directory by hand after
the first install with this version, or leave it: nothing reads it.

## Every plugin's install, from xymonapi 2.2.0

The plugins install with `./install.sh` at the repository's top, and `make`
is no longer used: the `Makefile`s are gone. What was
`make install XYMONHOME=...` in `plugins/NAME` is
`XYMONHOME=... ./install.sh install NAME`; `make install-client`,
`make uninstall`, `make uninstall-client`, `make venv` and
`make venv-client` are the same words after `./install.sh`, and with no
`NAME` they act on every plugin of the side, as the top `Makefile` did.
`PREFIX`, `MANDIR`, `DESTDIR` and `PYTHON` mean what they meant, from the
environment or as `NAME=value` arguments. What is installed, and where, is
unchanged: an install over the old one needs nothing more. The tests run
with `tests/run.sh` instead of `make test`.

## xymonapi 2.0.0

An API started before its launcher named it by its full path -- one whose
`pgrep -lf app.py` line shows a bare `app.py` -- is not found by the install,
which from now on stops the running API itself, and keeps running the old
code. Stop it once by its number, `kill PID`; xymonlaunch starts the new
one, which the next install finds.

`/client` is now `/plugins`, what it gives unchanged: the plugins installed
on the server, as a `.tar.gz`. Machines already installed need nothing; one
downloading the code from the server asks for
`https://SERVER/xymon/api/v1/plugins` instead.

## xymonapi 1.0.0

`/client` gives the code of the plugins installed on the server, as a
`.tar.gz`, instead of a setup script; its `name` and `format` options, and
the settings `XYMONAPI_PUBLIC_URL` and `XYMONAPI_REPO`, are gone. Machines
already set up keep their token and registrations and need nothing. To set
up one, or redo it: get the code -- from `/client` or a clone -- run
`make install-client` in `plugins/xymonapi-mcp`, then
`xymonapi-mcp register URL` (or `xymonapi-connect URL` for the API alone).
On the server, `make install` at the repository's top now also stages
`xymonapi-mcp` there, for `/client`.

## xymonapi-mcp, xymonapi-rag 0.1.0

The clients send a token and nothing else: `XYMONAPI_USER`,
`XYMONAPI_PASSWORD` and `XYMONAPI_PASSWORD_FILE` are no longer read. A
machine set up with a password gets 401: run `xymonapi-connect`, which gets
it a token.

## xymonapi 0.1.0

A user removed from the password file loses every client token at the first
use of one; putting the user back does not bring them back. Each of that
user's machines runs `xymonapi-connect` again for a new token.
