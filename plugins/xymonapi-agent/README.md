# xymonapi-agent

One command that asks an AI agent a question about Xymon and prints the
answer, with no one at the keyboard:

```sh
xymonapi-agent ask "which hosts are red, and since when?"
```

The agent is one of the coding agents you may already have on the machine
-- Claude Code, Codex or opencode -- run in its non-interactive mode with
[`xymonapi-mcp`](../xymonapi-mcp/README.md) as its only tool: the read-only
tools over the Xymon API, nothing else. Where `xymonapi-mcp` serves a person
typing into one of those agents, this serves a script: a cron job that mails
a morning summary, an alert script that attaches an explanation, a chat bot
that relays questions from a phone.
Every command, backend and setting is in
[`xymonapi-agent.1`](xymonapi-agent.1).

- **On your own machine**: the `xymonapi-agent` command, which runs an AI
  CLI you have installed and logged in. The model is that CLI's; this plugin
  has none and no API key.
- **On the Xymon server**: `/ask`, off by default: the API runs the same
  command as the Xymon user, which then needs an AI CLI and a backend of its
  own -- a hosted provider with a key, or a local model on this or another
  machine of yours -- named in a profile of that user ([A language
  model](../xymonapi/README.md#a-language-model)).

## Needs

- **[`xymonapi-mcp`](../xymonapi-mcp/README.md)** beside it, which
  `./install.sh install xymonapi-agent` installs first, with `xymonapi`'s client library -- and so a
  running [`xymonapi`](../xymonapi/README.md) on the Xymon server, reached as
  that README says. For the two search tools, `search_docs` and
  `search_history`, the server also runs
  [`xymonapi-rag`](../xymonapi-rag/README.md)'s index task; without it those
  two tools answer that there is no index, and the agent says so.
- **One agent CLI, installed and logged in by its own means**: Claude Code
  (`claude`), Codex (`codex`) or opencode (`opencode`). This plugin only
  runs it; it has no model of its own and no API key.
- Python 3.9 or later, and nothing else.

## On your own machine

```sh
cd xymon-plugins                               # the code: top README, Getting the code
./install.sh install xymonapi-agent     # under ~/.local; PREFIX=... for elsewhere
xymonapi-mcp register https://xymon.example.ch   # once: connects this machine to the API
xymonapi-agent backends                   # which CLI is here, and which answers
xymonapi-agent doctor                     # one question through the tools
```

`register` is `xymonapi-mcp`'s: it connects this machine to the API with
your password once, for a token of its own, and keeps the settings this
command hands to the MCP server. What it also registers with Claude Code and
Codex is for your own use of those agents; this command gives them the MCP
server itself, on each call, and tells Claude Code to use no other.

With one agent CLI on PATH, it is the one that answers. With several, name
it once:

```sh
export XYMONAPI_AGENT_BACKEND=claude     # or codex, opencode; --backend for one call
```

## On the Xymon server, behind the API

`XYMONHOME=... ./install.sh install xymonapi-agent` installs the agent beside
the API, with `xymonapi-mcp`. Then `POST /ask` on the API runs it, so a
caller anywhere -- a phone, a bot, a web page -- asks with the API's URL
and a token and needs no agent CLI of its own. The CLI must be installed
and logged in as the Xymon user, and `XYMONAPI_ASK=1` set in the API's
settings; [`xymonapi`'s README](../xymonapi/README.md#asking-in-words-ask)
says the rest. Profiles are then the Xymon user's, under its
`~/.config/xymonapi-agent/agents/`.

## Using it

```sh
xymonapi-agent ask "why is disk red on db02?"
xymonapi-agent ask --session nightly "what changed since yesterday evening?"
xymonapi-agent ask --session nightly "and which of those are still not green?"
xymonapi-agent ask --json "is anything red?" | jq -r .answer
```

`--session NAME` continues a conversation: the second question follows on
from the first, with the same agent. Claude Code continues a named session; with Codex and
opencode a named session starts fresh each time, and stderr says so --
their session ids are not stable enough in their documentation to keep.

## Agents: another Xymon, another tool set

What answers is an *agent*: its backends in order, its MCP servers, its
words after the fixed prompt, and the Xymon server it reads. The built-in
one, `xymon`, is the plugin as described above. A file under
`~/.config/xymonapi-agent/agents/` adds another:

```toml
# ~/.config/xymonapi-agent/agents/lab.toml -- the lab's Xymon
description = "the lab Xymon"
backend = ["claude", "opencode"]        # tried in order
site = "lab"
[env]
XYMONAPI_URL = "https://xymon-lab.example.ch"
XYMONAPI_TOKEN_FILE = "~/.config/xymon-api/xymon-lab.token"
```

```toml
# ~/.config/xymonapi-agent/agents/backup.toml -- another tool set entirely
description = "last night's restic backups"
backend = ["opencode"]
mcp = ["restic"]
prompt = "Backups are restic snapshots; a run is good when its snapshot exists."
[server.restic]
command = "/usr/local/bin/restic-mcp"
env = ["RESTIC_REPOSITORY", "RESTIC_PASSWORD_FILE"]
```

```sh
xymonapi-agent agents                                   # what is defined
xymonapi-agent --agent lab ask "anything red?"
xymonapi-agent --agent backup ask "did last night's run finish?"
export XYMONAPI_AGENT_AGENT=lab                          # the default for a shell
```

A profile chooses tools, words and target. It cannot loosen the sandbox:
the fixed part of the prompt and each backend's restriction stay, and the
tools allowed are exactly those of its `mcp` list. The manual page has
every key.

**A coordinator.** A profile that names other agents gets them as its
tools, one `ask_NAME` each, and routes a plain question to the right one:

```toml
# ~/.config/xymonapi-agent/agents/ops.toml
description = "routes a question to the right agent"
backend = ["claude"]
agents = ["xymon", "lab", "backup"]
```

```sh
xymonapi-agent --agent ops ask "anything wrong overnight, including the backups?"
```

Each ask runs that agent in a process of its own, with its own backends
and sandbox, never the coordinator's. Two guards stop runaway chains: a
depth of 2 coordinators, and 8 asks per question, both settings. A
coordinator can still have MCP servers of its own; by default it has none.

**Backends in order.** `backend` is a list, and so is
`XYMONAPI_AGENT_BACKEND=claude,opencode` or `--backend claude,opencode`: the
first on PATH runs; if it exits with an error, times out or answers
nothing, stderr says so and the next is tried. `--json` tells you which
one answered.

## How far each backend is held to the tools

The point of the plugin is that the agent reads Xymon through the MCP
server and does nothing else: no shell, no files, no web. A status text
comes from the monitored host, and a compromised host could write an
instruction into it; the system prompt says such text is data, and the
backend's flags are what make sure an instruction, if followed, has
nothing to reach. The three differ:

| backend | how it is held | how complete |
|---|---|---|
| `claude` | `--strict-mcp-config` (the agent's MCP servers, no other), `--tools ""` (no built-in tool), `--allowedTools mcp__xymon__*`, `--permission-mode dontAsk` | complete, as its documentation states each flag |
| `opencode` | a configuration file of its own for the call, project configuration disabled: the MCP server, every tool denied but the MCP servers', an agent with the system prompt | by configuration; your global `opencode` config still merges with it |
| `codex` | `--sandbox read-only`, overrides that give it the MCP server and turn its shell tool and web search off, `--ephemeral` | partial: the documentation does not promise the shell is gone, so the token file may be readable to the model |

`xymonapi-agent backends` prints the same for the machine it runs on;
`doctor` asks one question that only the health tool can answer. Prefer
`claude` where the API's token must not be readable to the model, and
`opencode` with a local model where the status texts must not leave the
machine. With Claude Code and Codex they go to the vendor's API, as they
do when you type the question yourself.

## In a script

The answer is text on stdout, and the exit status says whether there was
one: 0 for an answer, 1 when the backend failed or none is chosen, 77 when
no Python 3.9 is here. With `--json`, one object with `agent`, `backend`,
`session` and `answer`. A morning summary, in cron:

```sh
7 7 * * 1-5  xymonapi-agent ask "Summarise what went red or yellow in the last 24 hours, by host, and what is still not green." | mail -s "Xymon overnight" ops@example.ch
```

## Relation to `xymonapi-rag ask`

[`xymonapi-rag ask`](../xymonapi-rag/README.md) also answers a question,
from the passages its search finds, through an OpenAI-compatible endpoint
and a model you run; it has no tools, and needs no agent CLI. This command
answers with the tools -- it can read the board, the history and the
searches, and decide which -- and needs one of the three agents. Use
`xymonapi-rag ask` for "has this been seen before, and where?" with a local
model and nothing else installed; use this for anything that needs the
board's state now.
