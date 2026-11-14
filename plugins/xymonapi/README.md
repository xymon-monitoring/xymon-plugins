# xymonapi

The Xymon API gives, over HTTP and as JSON, the status board, its alarms
and hosts, the values in its RRD files, the graphs drawn from them, and the
history of colour changes with the status text saved at each. It only
reads, and changes nothing in Xymon.

- **On the Xymon server**: the API, one of Xymon's `xymonlaunch` tasks, with
  Xymon's own settings; it reads xymond's files and needs no credential.
- **On your own machine**: `xymonapi-connect`, which gets this machine a
  token, and the client library the other plugins read the API with.

Its operations, under `/xymon/api/v1`, all GET but for `/tokens`:

| path | gives |
|---|---|
| `/health` | whether xymond answers, its version, the search index, this API's version |
| `/states`, `/alarms`, `/entities` | the board, what is not ok, the hosts |
| `/pages` | the pages and groups of hosts.cfg, with the hosts in each |
| `/status` | one test's current status, text and acknowledgement included |
| `/series`, `/graphs` | the values of one RRD dataset; the PNG showgraph draws |
| `/events`, `/histlog` | the colour changes, newest first; the status text saved at one |
| `/search` | the manual-page and history passages nearest a question, when the server has a search index |
| `/plugins` | the plugins installed here, for other machines to install from |
| `/tokens` | a machine's own token, listed, made and revoked with your password |

[`xymonapi.8`](xymonapi.8) describes every operation and setting, for an
admin. [`openapi.yaml`](openapi.yaml), also served at `/openapi.json`, is the
contract: each path's exact answers, the closed list of errors, and the
numbered rules every implementation keeps.

## The API and what builds on it

Three plugins build on the API, and the four are one family:

| plugin | on the Xymon server | on your own machine | needs |
|---|---|---|---|
| `xymonapi` | the API, as one of xymonlaunch's tasks | `xymonapi-connect`, which gets this machine a token, and the client library the other plugins use | xymon >= 4.3.31 on the server; python >= 3.9 |
| [`xymonapi-mcp`](../xymonapi-mcp/README.md) | nothing runs: the plugin is staged for `/plugins` | an MCP server that gives an AI tool read-only tools over the API | xymonapi >= 0.1.0 beside it; the API's socket on the server, or the API over the network; python >= 3.9 |
| [`xymonapi-rag`](../xymonapi-rag/README.md) | the daily index of Xymon's manual pages and history, served at `/search` | `xymonapi-rag search` and `ask`: the same search, by meaning, from anywhere | xymonapi >= 0.1.0 beside it; python >= 3.9; a language model only for `ask` |
| [`xymonapi-agent`](../xymonapi-agent/README.md) | `/ask`: the API answers a question in words, off by default | `xymonapi-agent`: one command that asks an AI CLI -- Claude Code, Codex or opencode, headless -- with the MCP server as its only tool | xymonapi-mcp >= 0.1.0 beside it; one of the AI CLIs, installed and logged in; python >= 3.9 |

The API is the line between the Xymon server and your own machine. On the
server, the API, the daily index and `/ask` are started by xymonlaunch as
the Xymon user, read xymond's own files, and need no credential. On your own
machine, `xymonapi-connect`, the MCP server your AI tool starts,
`xymonapi-rag search` and `xymonapi-agent` go through the API, with a token
or, on the server itself, its socket. **No language model is needed for the
monitoring data to reach your AI tool**: only `xymonapi-agent`, `/ask` and
`xymonapi-rag ask` call one.

### A language model

None of the plugins needs one to do its work. The API, the MCP server, the
index and the search run without any. Three things call a model, and each
says whose:

- **Your AI tool's**, with the MCP server: the model is whatever Claude
  Code, Codex, opencode or Claude Desktop runs -- a subscription, an API key
  of yours, or a local model. The Xymon server knows nothing about it. What
  the tools return, status texts included, goes to that tool's provider;
  with a local model it stays on your machine.
- **The server's**, for `/ask`: the Xymon user runs an AI CLI of its own,
  and needs a backend for it, of one of three kinds -- a hosted provider
  with an API key; a local model on the server itself, through Ollama or LM
  Studio; or a local model on another machine of yours, reached by URL. A
  profile under the Xymon user's `~/.config/xymonapi-agent/agents/` names
  it, as [`xymonapi-agent`'s README](../xymonapi-agent/README.md#agents-another-xymon-another-tool-set)
  shows; `xymonapi-agent doctor`, run as that user, says whether it
  answers. With none, `/ask` stays off and everything else works.
- **A model you run**, for `xymonapi-rag ask`: an OpenAI-compatible
  endpoint, Ollama by default, named by `XYMONAPI_RAG_LLM_URL`; no tools,
  no CLI.

## Requirements

- Xymon 4.3.31 or later on the server: the API's settings go in
  `xymonserver.d/`, which Xymon reads from 4.3.31; on 4.3.30 a file there is
  ignored, and with it the password the API should ask for. The install
  refuses an older Xymon unless given `--force`.
- Python 3.9 or later, with the modules in
  [`requirements.txt`](requirements.txt): how the install finds or makes a
  Python with them is in the [top README](../README.md#installing-a-plugin).
- `rrdtool`, for `/series`; a web server running Xymon's CGI programs at
  `XYMONSERVERCGIURL`, for `/graphs`; Apache's `htpasswd`, when a password
  file is used.

## On the Xymon server

```sh
XYMONHOME=/usr/lib/xymon/server ./install.sh install-server xymonapi
```

Besides the code, the task and the manual page, which every plugin
installs ([top README](../README.md#installing-a-plugin)), it installs the web
server snippets `$XYMONHOME/ext/xymonapi/xymonapi-{apache,nginx,lighttpd}.conf`,
for [other machines](#reaching-it-from-another-machine), and keeps your edits
to them.
Xymon's own install links `$XYMONHOME/ext` and `$XYMONHOME/etc` to wherever
those really are -- `/etc/xymon` on many installations -- so the files land
there; with `DESTDIR`, the staged directories are plain ones.

Then turn it on, `XYMONHOME=/usr/lib/xymon/server ./install.sh enable-server xymonapi`, and check:

```sh
curl http://127.0.0.1:1986/xymon/api/v1/health              # the port: 401 means it runs and asks for a user
curl --unix-socket "$XYMONVAR/xymonapi/api.sock" http://localhost/xymon/api/v1/health
```

The port asks for one of its [users](#users), `-u alice`, whatever the
address. The socket, `$XYMONVAR/xymonapi/api.sock`, is for the programs of
the server itself and asks none: its permissions let the Xymon user and its
group in, and nobody else. The plugins' commands take it by default
there (`xymonapi.8`, `XYMONAPI_SOCKET`).

Updating: install again. The install stops the running API, which would go
on with the code it loaded, and says so; xymonlaunch starts the new.
`./install.sh uninstall-server xymonapi` removes the snippets with the rest of
`ext/xymonapi`, which the web server's optional include then skips, and keeps
the tokens file, `$XYMONAPI_TOKENS`. A snippet an older install wrote in
`$XYMONHOME/etc` is left there: the next install copies it, your edits with
it, into `ext/xymonapi`, and says so; include the new one, then remove the
old.

## Asking in words: /ask

With [`xymonapi-agent`](../xymonapi-agent/README.md) installed beside the
API (`./install.sh install-server xymonapi-agent`, which brings `xymonapi-mcp`), the API
can answer a question in words: `POST /ask` with `{"question": "..."}`
runs the agent as the Xymon user, with an agent CLI that user has
installed and logged in -- Claude Code, Codex or opencode -- and the Xymon
MCP server as its only tool, and answers `{"answer": ..., "agent": ...,
"backend": ...}`. Phones, bots and web pages then need only the API's URL
and a token. It is off until `XYMONAPI_ASK=1` is in the file under
`xymonserver.d/`, with `XYMONAPI_AGENT_BACKEND` and the rest of
`xymonapi-agent`'s settings beside it; a caller asks one question at a
time and `XYMONAPI_ASK_PER_HOUR` an hour. Sessions are per caller. Check it
as the Xymon user with `xymonapi-agent doctor`, then:

```sh
curl -s -H "Authorization: Bearer $(cat ~/.config/xymon-api/xymon.token)" \
  -H 'Content-Type: application/json' -d '{"question":"anything red, and since when?"}' \
  https://xymon.example.ch/xymon/api/v1/ask
```

Every setting and limit is in [`xymonapi.8`](xymonapi.8), under /ask.

## Users

The API's users are those of Xymon's own web password file,
`$XYMONHOME/etc/xymonpasswd`: the same names and passwords as the Xymon web
pages. Add one with Xymon's `useradm.cgi`, or by hand:

```sh
htpasswd -B "$XYMONHOME/etc/xymonpasswd" alice
```

The API reads the file at each request: nothing to restart. Without that
file the API does not start, and says so: `XYMONAPI_PASSWD` names another
file, or, set empty, opens the API to anyone who reaches it, as
`xymonapi.8` says.

## Reaching it from another machine

Its port listens on 127.0.0.1 unless told otherwise, and asks the password
there whatever the address; the socket above never leaves the machine. From
another machine, use HTTPS, one of -- each with the URL an API client is
then given, in `xymonapi-connect`, `register` or `XYMONAPI_URL`: the scheme,
the host and the port, without `/xymon/api/v1`, which the client library
adds:

- **Its own HTTPS.** Where xymond has a certificate for TLS (`xymon-tls(7)`,
  from Xymon pull requests #617–#623, not yet merged), the API finds it in
  `etc/tls/` and speaks HTTPS by itself; or name any certificate and key in
  `XYMONAPI_TLS_CERT` and `_KEY`. Open the port with
  `XYMONAPI_LISTEN="0.0.0.0:1986"`. The URL: `https://xymon.example.ch:1986`.
- **The web server in front of it.** Include the snippet for your web
  server, in `$XYMONHOME/ext/xymonapi/`, in its HTTPS part, so that it is
  skipped once the plugin is gone: `IncludeOptional
  .../ext/xymonapi/xymonapi-apache.conf` on Apache, `include
  .../ext/xymonapi/xymonapi-nginx*.conf;` on nginx, `include
  ".../ext/xymonapi/xymonapi-lighttpd*.conf"` on lighttpd -- a plain include
  of a file that is gone stops lighttpd and Apache from starting. That gives
  one hostname for the pages and the API. The URL: the address your Xymon
  pages are at -- the same web server and the same port -- without the
  path: pages at `https://xymon.example.ch:8443/xymon/` mean the URL
  `https://xymon.example.ch:8443`, and pages at
  `https://xymon.example.ch/xymon/` the URL `https://xymon.example.ch`.
- **An SSH tunnel**, for one person:
  `ssh -L 1986:127.0.0.1:1986 xymon-server`. The URL:
  `http://127.0.0.1:1986`, as if local.

Plain HTTP across a network carries the password, the tokens and the status
texts readable, as port 1984 does: keep it to a network where the Xymon pages
themselves are plain and trusted. Whichever you choose, keep secrets out of
the texts: `XYMONAPI_HIDE` names a file of regular expressions whose matches
come out as `[hidden]`, in every text and in the search index.

## On your own machine

A machine that reads the API -- a laptop, say, or the server itself when you
work there -- needs the API's client library and a token of its own, and for
that a POSIX shell, `curl` and Python 3.9 or later, nothing else:

```sh
# Only when the certificate is the server's own, not one the machine trusts:
# copy it where xymonapi-connect looks, over a channel you already trust.
mkdir -p ~/.config/xymon-api
scp xymon.example.ch:/etc/xymon/tls/xymond.pem ~/.config/xymon-api/xymon-ca.pem

cd xymon-plugins                         # the code: top README, Getting the code
./install.sh install-tools xymonapi     # under ~/.local; PREFIX=... for elsewhere
xymonapi-connect https://xymon.example.ch   # the URL: as reached, above
```

`xymonapi-connect` asks for your user and password once -- one of the API's
[users](#users) -- to get this machine a token, kept in
`~/.config/xymon-api/xymon.token`; the password is not kept. Run again, it
keeps a token that works, says when this machine's library and the API run
different versions, and prints the settings a program reading the API
needs. A second server gets a name of its own:
`xymonapi-connect https://lab.example.ch xymon-lab`. `/tokens` lists your
machines and revokes one, and removing a user from the password file
revokes all of theirs. Every detail is in
[`xymonapi-connect.1`](xymonapi-connect.1).

`./install.sh uninstall-tools xymonapi` keeps the token: revoke it with `/tokens`, or delete
`~/.config/xymon-api/xymon.token`.
