# xymonapi-mcp

An MCP server: it gives an AI tool that speaks the Model Context Protocol
-- Claude Code, Claude Desktop, Codex, opencode and others -- read-only tools
over the [Xymon API](../xymonapi/README.md): `health`, `states`, `alarms`,
`entities`, `status`, `series`, and two searches, `search_docs` and
`search_history`, which ask the API's `/search`.
Every tool and setting is in [`xymonapi-mcp.1`](xymonapi-mcp.1).

- **On the Xymon server**: nothing runs; the plugin is staged for `/plugins`.
- **On your own machine**: the MCP server, which your AI tool starts and
  talks to over stdin and stdout. It is a server in MCP's vocabulary and a
  command in this tree's: it runs where the AI tool runs, the Xymon server
  included, and reads the API as any API client does. The model is the AI
  tool's own; this plugin has none.

## Needs

- **A running [`xymonapi`](../xymonapi/README.md)** on the Xymon server,
  reached through its socket from that machine and over the network from
  any other. `./install.sh install xymonapi-mcp` installs `xymonapi`'s client library beside
  this plugin; the API itself is installed and enabled on the server, by its
  own README or by this plugin's server install there.
- Python 3.9 or later, and nothing else: it speaks the protocol with the
  standard library.

## On your own machine, where the AI tool runs

```sh
cd xymon-plugins                             # the code: top README, Getting the code
./install.sh install xymonapi-mcp     # under ~/.local; PREFIX=... for elsewhere
xymonapi-mcp register https://xymon.example.ch
```

The URL is the API's as this machine reaches it, port included when it is
not 443 -- [`xymonapi`'s
README](../xymonapi/README.md#reaching-it-from-another-machine) gives it for
each way of reaching it. `register` connects this machine to the API with
`xymonapi-connect` -- your password once, for a token of its own, as
[`xymonapi`'s README](../xymonapi/README.md#on-your-own-machine) says -- then
registers the server with Claude Code and Codex as `xymon`. Then ask your AI
tool "which hosts are red?". `register URL xymon-lab` names a second
server; an AI tool that is neither of those two is [registered by
hand](#registering-it-by-hand).

On the Xymon server itself, give `register` the API's socket instead of a
URL: `unix:$XYMONVAR/xymonapi/api.sock`. Nothing is asked and no token is
kept, since the socket's permissions already say who may read the API
(`xymonapi.8`, `XYMONAPI_SOCKET`).

`./install.sh remove xymonapi-mcp` removes this plugin and says what `register` did
besides, to undo by hand: the registrations in Claude Code and Codex, and
this machine's token.

## On the Xymon server

`XYMONHOME=... ./install.sh install xymonapi-mcp` installs the API first, when it is not there,
and stages this plugin in what the API serves at `/plugins`, for the
machines above to install it from, at the server's version. It installs no
command on the server: an MCP server runs where the AI tool runs.

An AI tool that runs on the server machine itself is one of those
machines: run `./install.sh install xymonapi-mcp` there as well, as yourself, and
`register` with the API's socket, as above.

## Registering it by hand

For Claude Code, once, at user scope so every project has it:

```sh
claude mcp add --scope user xymon \
  -e XYMONAPI_URL=https://xymon.example.ch \
  -e XYMONAPI_TOKEN_FILE=$HOME/.config/xymon-api/xymon.token \
  -- ~/.local/bin/xymonapi-mcp
```

For Codex, the same with `--env` for `-e` and no scope:
`codex mcp add xymon --env ... -- ~/.local/bin/xymonapi-mcp`.

Most other AI tools read this JSON: Claude Desktop in
`claude_desktop_config.json`, Gemini CLI in `~/.gemini/settings.json`,
Cursor in `~/.cursor/mcp.json`; VS Code reads `.vscode/mcp.json`, with
`servers` for `mcpServers`. JSON expands nothing, so write the paths in full:

```json
{
  "mcpServers": {
    "xymon": {
      "command": "/home/me/.local/bin/xymonapi-mcp",
      "env": {
        "XYMONAPI_URL": "https://xymon.example.ch",
        "XYMONAPI_TOKEN_FILE": "/home/me/.config/xymon-api/xymon.token"
      }
    }
  }
}
```

opencode reads its own form, in `~/.config/opencode/opencode.json` or a
project's `opencode.json`: under `mcp`, with `"type": "local"`, the command
as a list, and `environment` for `env`.

- The token file holds what `POST /tokens` answers to one of the API's
  [users](../xymonapi/README.md#users), alone, mode 600; it is the only
  credential sent. Leave it out when the API asks for no password.
- Add `XYMONAPI_CA` when the server's certificate is its own, and
  `XYMONAPI_PYTHON` when the `python3` on `PATH` is older than 3.9 and no
  virtualenv sits beside the plugins (`./install.sh venv` makes one).
- For two Xymon servers, register twice, as `xymon-prod` and `xymon-lab`,
  each with its own URL and token file.

## What it cannot do

- An AI tool in a web browser -- claude.ai, ChatGPT -- cannot use it: it
  reaches an MCP server from its provider's cloud, so the server would have
  to be open to the internet. Claude Desktop runs on your machine instead.
- An online AI tool sends what the tools return to its provider. With a
  local model -- opencode with LM Studio or Ollama, for instance -- nothing
  leaves your network; a model too small reads the answers wrong.
- The two searches answer an error until the server has an index.
