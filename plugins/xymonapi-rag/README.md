# xymonapi-rag

It finds the passages of Xymon's manual pages and history that a question is
about, by what they mean rather than the words they share. Every command and
setting is in [`xymonapi-rag.1`](xymonapi-rag.1).

- **On the Xymon server**: the daily index task. It reads the pages and
  xymond's history files where they are, needs no credential, and the
  [API](../xymonapi/README.md) serves what it writes at `/search`. No
  language model is involved.
- **On your own machine**: `xymonapi-rag search`, the same search through
  the API, and `ask`, which hands the passages found to a language model you
  run.

## Needs

- **[`xymonapi`](../xymonapi/README.md)**: on the server, the API, which
  serves the index at `/search` and whose code the index task reads the
  history with; elsewhere, its client library. Either install here brings
  the one it needs.
- Python 3.9 or later. The modules in [`requirements.txt`](requirements.txt)
  are needed on the server, and on a machine that keeps an index of its own;
  how the install finds or makes a Python with them is in the [top
  README](../README.md#installing-a-plugin).

## On the Xymon server

```sh
XYMONHOME=/usr/lib/xymon/server ./install.sh install-server xymonapi-rag
```

It installs the daily index task, off. To turn it on, put
`XYMONAPI_RAG_DOCS` -- a directory with Xymon's manual pages;
`/usr/share/man` will do -- in a file under `xymonserver.d/`, then run
`XYMONHOME=... ./install.sh enable-server xymonapi-rag`. The API's own task
must run too, for the search to be served.

The task reads the history from xymond's own files, as the API does, and
needs no credential. Its first run downloads a 65 MB embedding model and
takes about a minute; the next ones embed only what is new and take
seconds. `XYMONAPI_RAG_OFFLINE` forbids the download once the cache is
seeded. The index holds the last 30 days of history, the newest 5000
changes at most, and the API serves it as soon as it is written.

From a shell on the server, the installed launcher searches with no
setting and no token when run through `xymoncmd`, which gives it Xymon's
settings: as the Xymon user it reads the index where the task wrote it,
and otherwise asks the API through its socket, `$XYMONVAR/xymonapi/api.sock`
(`xymonapi.8`, `XYMONAPI_SOCKET`):

```sh
xymoncmd /usr/lib/xymon/server/ext/xymonapi-rag/xymonapi-rag.sh search "what does purple mean"
```

Without `xymoncmd`, set `XYMONAPI_URL=unix:` followed by the socket's path.

`./install.sh uninstall-server xymonapi-rag` keeps the index, `$XYMONAPI_RAG_INDEX`.

## On your own machine

```sh
cd xymon-plugins                             # the code: top README, Getting the code
./install.sh install-tools xymonapi-rag     # under ~/.local; PREFIX=... for elsewhere
set -a; eval "$(xymonapi-connect https://xymon.example.ch)"; set +a
xymonapi-rag search "what does purple mean"
xymonapi-rag ask "has /boot filled up before, and where?"
```

The URL is the API's as this machine reaches it, port included when it is
not 443, as [`xymonapi`'s
README](../xymonapi/README.md#reaching-it-from-another-machine) gives it.
`xymonapi-connect`, installed with the API's client library, gets this machine its token
with your password once, as [`xymonapi`'s
README](../xymonapi/README.md#on-your-own-machine) says, and prints the
settings `xymonapi-rag` reads; the `eval` puts them in the shell.

`search` uses the server's index when there is none here. `ask` hands the
passages to a language model speaking the OpenAI-compatible API -- a local
Ollama by default, LM Studio with two settings. Pick the model with care: a
small one such as `llama3.2` answers in a second but makes things up, where a
larger one says when the passages do not hold the answer.

`./install.sh uninstall-tools xymonapi-rag` keeps any index here, `$XYMONAPI_RAG_INDEX`.

`eval` scores the search against a file of questions;
[`tests/eval/docs.json`](../../tests/eval/docs.json) is the one CI runs.
