# Plugins

Each directory here is one plugin: a `PLUGIN` file, a README, a manual page,
tests and its code. What installing one guarantees is in
[`SPEC.md`](../SPEC.md).

## The plugins

| plugin | what it is |
|---|---|
| [`xymonapi`](xymonapi/README.md) | a read-only HTTP/JSON API to a Xymon server, with `xymonapi-connect` and a client library |
| [`xymonapi-mcp`](xymonapi-mcp/README.md) | an MCP server: read-only tools over the API for an AI tool |
| [`xymonapi-rag`](xymonapi-rag/README.md) | search of Xymon's manual pages and history by meaning |
| [`xymonapi-agent`](xymonapi-agent/README.md) | one command that asks an AI CLI about Xymon; the API's `/ask` |
| [`clientage`](clientage/README.md) | the age of a Xymon client's last message, as a column of its host; the example of a client part |
| [`xymon-plugin`](xymon-plugin/README.md) | the installer itself, and the `plugins` column that says when a newer release is out |

How the API's plugins fit together:
[`xymonapi`'s README](xymonapi/README.md#the-api-and-what-builds-on-it).

## Installing a plugin

With `./xymon-plugin` at the repository's top (a POSIX shell script). A
plugin has up to two parts; install the one the machine plays:

| part | where, as whom | command |
|---|---|---|
| server | the Xymon server, as the user that owns it (often root) | `XYMONHOME=/usr/lib/xymon/server ./xymon-plugin install --server NAME` |
| tools | any machine that reads the API, as yourself | `./xymon-plugin install --tools NAME` |

- `--all` in place of `NAME`: every plugin of that part. A plugin's needs are
  installed with it.
- A server task is installed **off**: `enable --server NAME` turns it on.
- Python 3.9 or later; a plugin that needs modules gets a virtualenv beside
  the plugins, from a Python that has them, or from PyPI when you agree
  ([details](xymon-plugin/README.md#python)).
- Run with no verb on a terminal, `./xymon-plugin` shows where things stand
  and offers what applies.

## Everyday commands

| to | run |
|---|---|
| see what is installed | `./xymon-plugin status --server` (or `--tools`) |
| know if a newer release is out | `./xymon-plugin outdated` |
| update | `./xymon-plugin update --server` (or `--tools`) |
| turn a task on / off | `./xymon-plugin enable --server NAME` / `disable` |
| check what changed since the install | `./xymon-plugin verify` |
| remove leftovers of a deleted plugin | `./xymon-plugin clean --server --all` |
| uninstall | `./xymon-plugin remove --server NAME` (or `--tools`) |

An update keeps your task file, web server snippets and settings, and
whether a task is on; the API takes up its new code by itself.

Every verb, setting, file and exit status:
[`xymon-plugin`'s README](xymon-plugin/README.md#reference) and
[xymon-plugin(8)](xymon-plugin/xymon-plugin.8).

## Getting the code from the server

A machine that only reads the API can take the plugins from the Xymon
server, at the versions it runs:

```sh
curl --cacert ~/.config/xymonapi/xymon-ca.pem https://xymon.example.ch/xymon/api/v1/plugins | tar xz
```

The URL is the API's, as [`xymonapi`'s README](xymonapi/README.md) gives it,
followed by `/xymon/api/v1/plugins`. Never `-k`: unchecked code could be
anyone's.
