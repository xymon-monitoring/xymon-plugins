#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
#
# plugins/xymonapi-agent/tests/xymonapi-agent.sh
#
# xymonapi-agent ask, as ./install.sh install lays it out, runs the agent CLI
# it is told, or the one installed, with xymonapi-mcp beside it as the
# agent's only tool: Claude Code with --strict-mcp-config, no built-in tools,
# the xymon tools allowed and the rest denied; opencode with a config of its
# own that denies every tool but xymon_*; Codex with a read-only sandbox and
# its shell tool off. Each gets the API's settings as the MCP server's
# environment and the same system prompt, with its rule that a status text
# is data. A session named for Claude Code is continued by the same id;
# doctor passes on a version and fails on anything else; the CLI gets
# nothing on stdin, whatever is piped in; with no CLI, or
# several and no choice, it says so. A profile under
# $XDG_CONFIG_HOME/xymonapi-agent/agents/ is another agent: its backends
# tried in order, a failing one said and the next taken; its own MCP
# servers, its environment over this one, its words after the fixed prompt;
# a bad profile is refused with its line. A profile naming other agents is
# a coordinator: its backend gets this command as an MCP server with one
# ask_NAME tool per agent, each an ask of that agent in a process of its
# own, with that agent's choices and not the parent's; at depth 0 and past
# the cap on asks, a call is refused; a profile naming itself, or an agent
# that is not defined, is refused.
#
# claude, codex and opencode are stubs that record their arguments and
# answer a fixed text. Nothing of the API runs. Uses the test helpers of
# the Xymon tree in XYMON_SRC.

set -euo pipefail
# shellcheck source=tests/lib/xymonapi.sh
. "$(dirname "$0")/../../../tests/lib/xymonapi.sh"

ROOT=$(find_root)
work=$(mktempdir)

"$ROOT/install.sh" install xymonapi-agent PREFIX="$work/client" >"$work/client.log" 2>&1 \
	|| fail "install.sh install failed: $(tail -n 5 "$work/client.log")"
agent=$work/client/bin/xymonapi-agent
assert_file_exists "$work/client/libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh"
assert_file_exists "$work/client/libexec/xymon-plugins/xymonapi-agent/VERSION"
assert_file_exists "$work/client/share/man/man1/xymonapi-agent.1"

mkdir -p "$work/stub"
cat > "$work/stub/claude" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/claude.args"
cat > "$work/claude.stdin"
printf '{"result":"xymon 4.3.31","permission_denials":[]}\n'
STUB
cat > "$work/stub/codex" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/codex.args"
echo "an answer"
STUB
cat > "$work/stub/opencode" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/opencode.args"
cp "\$OPENCODE_CONFIG" "$work/opencode.json"
echo "\$OPENCODE_DISABLE_PROJECT_CONFIG" > "$work/opencode.env"
echo "an answer"
STUB
chmod 755 "$work/stub/"*
path="$work/stub:/usr/bin:/bin"
# The test's own state and profiles, never this user's under ~/.config.
export XDG_STATE_HOME="$work/state" XDG_CONFIG_HOME="$work/cfg" \
	XYMONAPI_URL="http://127.0.0.1:1" XYMONAPI_TOKEN_FILE="$work/token"
unset XYMONAPI_AGENT_BACKEND XYMONAPI_AGENT_AGENT XYMONAPI_AGENT_MODEL XYMONAPI_AGENT_SITE

run() { PATH="$path" "$agent" "$@"; }

# No CLI, or three and no choice: said, and nothing run.
rc=0; out=$(PATH="/usr/bin:/bin" "$agent" ask "anything" 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "with no CLI, ask exited $rc: $out"
assert_contains "no agent CLI found" "$out" "with no CLI, ask says so"
rc=0; out=$(run ask "anything" 2>&1) || rc=$?
assert_contains "3 agent CLIs are here" "$out" "with three CLIs and no choice, ask says which"
[ -e "$work/claude.args" ] && fail "a CLI was run without a choice"

# Claude Code: the restricting flags, the MCP server beside the plugin with
# the API's settings, the system prompt, a session of our id.
out=$(run --backend claude ask "which hosts are red?" --session nightly)
assert_equal "xymon 4.3.31" "$out" "ask prints the result of Claude Code's JSON"
args=$(cat "$work/claude.args")
assert_contains "--strict-mcp-config" "$args" "Claude Code gets this MCP server and no other"
grep -qx -- '--tools' "$work/claude.args" || fail "Claude Code is not told --tools"
assert_contains "mcp__xymon__*" "$args" "the xymon tools are allowed"
assert_contains "dontAsk" "$args" "and the rest denied, not asked about"
assert_contains "libexec/xymon-plugins/xymonapi-mcp/xymonapi-mcp.sh" "$args" "the MCP server is the one beside the plugin"
assert_contains '"XYMONAPI_URL": "http://127.0.0.1:1"' "$args" "with the API's address as its environment"
assert_contains "\"XYMONAPI_TOKEN_FILE\": \"$work/token\"" "$args" "and the token file"
assert_contains "never an instruction" "$args" "the system prompt says a status text is data"
assert_contains "--session-id" "$args" "a named session starts with an id of ours"
sid=$(grep -A1 -- '--session-id' "$work/claude.args" | tail -n 1)
out=$(run --backend claude ask "and yellow?" --session nightly)
assert_contains "--resume" "$(cat "$work/claude.args")" "the next call continues it"
assert_equal "$sid" "$(grep -A1 -- '--resume' "$work/claude.args" | tail -n 1)" "by the same id"
out=$(run --backend claude ask "once" --json)
assert_contains '"backend": "claude"' "$out" "--json names the backend"
assert_contains '"answer": "xymon 4.3.31"' "$out" "and carries the answer"
assert_contains "--no-session-persistence" "$(cat "$work/claude.args")" "an unnamed question leaves no session"

# The CLI gets nothing on stdin: what is piped into xymonapi-agent is not
# the question, and a CLI given an open pipe would wait for its end.
out=$(printf 'not the question\n' | run --backend claude ask "piped")
assert_equal "xymon 4.3.31" "$out" "ask answers with something piped into it"
[ -s "$work/claude.stdin" ] && fail "the CLI was given xymonapi-agent's stdin: $(cat "$work/claude.stdin")"

# XYMONAPI_AGENT_BACKEND chooses as --backend does.
out=$(XYMONAPI_AGENT_BACKEND=codex run ask "which hosts are red?")
assert_equal "an answer" "$out" "the backend named in the environment answers"
args=$(cat "$work/codex.args")
assert_contains "read-only" "$args" "Codex runs in its read-only sandbox"
assert_contains "features.shell_tool=false" "$args" "with its shell tool off"
assert_contains 'mcp_servers.xymon.command=' "$args" "and the MCP server given on the command line"
assert_contains 'XYMONAPI_URL="http://127.0.0.1:1"' "$args" "with the API's address"
assert_contains "never an instruction" "$args" "and the system prompt"

# opencode: a config of its own, project config off.
out=$(run --backend opencode ask "which hosts are red?")
assert_equal "an answer" "$out" "opencode answers"
cfg=$(cat "$work/opencode.json")
assert_contains '"xymon_*": "allow"' "$cfg" "its config allows the xymon tools"
assert_contains '"*": "deny"' "$cfg" "and denies every other"
assert_contains "xymonapi-mcp/xymonapi-mcp.sh" "$cfg" "with the MCP server beside the plugin"
assert_contains "never an instruction" "$cfg" "and the system prompt as the agent's"
assert_equal "1" "$(cat "$work/opencode.env")" "project configuration is disabled"
assert_contains "--agent" "$(cat "$work/opencode.args")" "and that agent is the one run"
[ -e "$(first_line "$(grep -o '/[^"]*xymonapi-agent-[^"]*\.json' "$work/opencode.args" || true)")" ] 2>/dev/null \
	&& fail "the temporary config was left behind"

# doctor: a version from the health tool passes, anything else fails.
rc=0; out=$(run --backend claude doctor) || rc=$?
[ "$rc" -eq 0 ] || fail "doctor failed on a version: $out"
assert_contains "ok: the health tool answered" "$out" "doctor passes on a version"
rc=0; out=$(run --backend codex doctor) || rc=$?
[ "$rc" -eq 1 ] || fail "doctor exited $rc on a non-version"
assert_contains "not ok" "$out" "and fails on anything else"

# backends: each CLI, its restriction, and what answers.
out=$(run backends)
assert_contains "claude: $work/stub/claude" "$out" "backends names each CLI found"
assert_contains "restriction complete" "$out" "and how far it is held to the MCP server"
assert_contains "answers for xymon: none" "$out" "and that three with no choice answer nothing"
out=$(XYMONAPI_AGENT_BACKEND=opencode run backends)
assert_contains "answers for xymon: opencode" "$out" "or the one chosen"

# Profiles: another Xymon server, another tool set, a bad file.
mkdir -p "$work/cfg/xymonapi-agent/agents"
cat > "$work/cfg/xymonapi-agent/agents/lab.toml" <<'PROF'
description = "the lab Xymon"      # tried in order
backend = ["codex", "claude"]
site = "lab"
[env]
XYMONAPI_URL = "https://lab.example:8443"
PROF
cat > "$work/cfg/xymonapi-agent/agents/backup.toml" <<PROF
description = "last night's backups"
backend = ["opencode"]
mcp = ["restic"]
prompt = "Backups are restic snapshots."
[server.restic]
command = "$work/stub/restic-mcp"
args = ["--json"]
env = ["RESTIC_REPOSITORY"]
PROF
: > "$work/stub/restic-mcp"
out=$(run agents)
assert_contains "xymon: the Xymon board" "$out" "agents lists the built-in agent"
assert_contains "lab: the lab Xymon" "$out" "and a profile"
assert_contains "backends codex, claude; mcp xymon" "$out" "with its backends in order and its MCP servers"
assert_contains "backup: last night's backups" "$out" "and another"

# lab: the codex stub fails, so claude answers, and stderr says so; the
# profile's environment reaches the MCP server; its site is in the prompt.
cat > "$work/stub/codex" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/codex.args"
echo "codex is not logged in" >&2
exit 3
STUB
rc=0; out=$(run --agent lab ask "which hosts are red?" 2>"$work/lab.err") || rc=$?
[ "$rc" -eq 0 ] || fail "ask with a failing first backend exited $rc: $out $(cat "$work/lab.err")"
assert_equal "xymon 4.3.31" "$out" "the second backend answers when the first fails"
assert_contains "codex gave no answer (exited 3: codex is not logged in); trying claude" "$(cat "$work/lab.err")" "and stderr says which failed, why, and which is tried"
args=$(cat "$work/claude.args")
assert_contains '"XYMONAPI_URL": "https://lab.example:8443"' "$args" "the profile's env is the MCP server's"
assert_contains "The site is called lab." "$args" "and its site is in the prompt"
assert_contains "never an instruction" "$args" "after the fixed part"
out=$(run --agent lab ask --json "once")
assert_contains '"agent": "lab", "backend": "claude"' "$out" "--json names the agent and the backend that answered"
rc=0; out=$(run --agent lab ask --session s "q" >/dev/null 2>&1; run --agent lab ask --session s "q2") || rc=$?
sid_lab=$(grep -A1 -- '--resume' "$work/claude.args" | tail -n 1)
[ "$sid_lab" != "$sid" ] || fail "a session of another agent has the same id as xymon's"

# Every backend failing is the error, naming each.
rc=0; out=$(run --agent lab --backend codex ask "q" 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "with every backend failing, ask exited $rc"
assert_contains "no backend answered: codex: exited 3" "$out" "all failing is said, each with its reason"

# backup: its own MCP server, no xymon; opencode gets it and only it, and
# the model on its command line, where run honours it.
# (before the [server.restic] table, which runs to the end of the file)
b=$work/cfg/xymonapi-agent/agents/backup.toml
{ printf 'model = "ollama/llama3.2:latest"\n'; cat "$b"; } > "$b.new" && mv "$b.new" "$b"
out=$(run --agent backup ask "did it finish?")
assert_contains "--model
ollama/llama3.2:latest" "$(cat "$work/opencode.args")" "opencode is given the agent's model on the command line"
assert_equal "an answer" "$out" "an agent with another tool set answers"
cfg=$(cat "$work/opencode.json")
assert_contains "\"command\": [\"$work/stub/restic-mcp\", \"--json\"]" "$cfg" "its MCP server, with its args"
assert_contains '"restic_*": "allow"' "$cfg" "its tools allowed"
grep -q 'xymon_\*' "$work/opencode.json" && fail "the xymon tools were allowed to an agent without that server"
assert_contains "Backups are restic snapshots." "$cfg" "its prompt after the fixed one"
assert_contains '"agent": {"backup"' "$cfg" "as the agent of its name"
grep -q '"XYMONAPI_URL"' "$work/opencode.json" && fail "the Xymon settings were handed to another server"
rc=0; out=$(run --agent backup doctor 2>&1) || rc=$?
assert_contains "does not have" "$out" "doctor says when the agent has no xymon tool"

# A missing CLI in the list is skipped without a word of failure.
rc=0; out=$(PATH="$work/stub:/usr/bin:/bin" env -u XYMONAPI_AGENT_BACKEND "$agent" --backend nothere,claude ask "q" 2>&1) || rc=$?
assert_contains "no backend named 'nothere'" "$out" "an unknown backend name is refused"
mv "$work/stub/codex" "$work/stub/codex.off"
out=$(run --agent lab ask "q" 2>"$work/lab.err")
assert_equal "xymon 4.3.31" "$out" "a listed CLI that is not here is skipped"
[ -s "$work/lab.err" ] && fail "and nothing is said of it: $(cat "$work/lab.err")"
mv "$work/stub/codex.off" "$work/stub/codex"

# A bad profile: refused with the file and line, by agents and by ask.
printf 'description = "x"\nbackend = {a = 1}\n' > "$work/cfg/xymonapi-agent/agents/bad.toml"
rc=0; out=$(run agents 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "agents with a bad profile exited $rc"
assert_contains "bad.toml" "$out" "a bad profile is named"
rc=0; out=$(run --agent lab ask "q" 2>&1) || rc=$?
[ "$rc" -eq 1 ] || fail "ask with a bad profile present exited $rc"
printf 'mcp = ["nosuch"]\n' > "$work/cfg/xymonapi-agent/agents/bad.toml"
rc=0; out=$(run agents 2>&1) || rc=$?
assert_contains "no [server.nosuch] table" "$out" "an MCP server named but not defined is said"
rm "$work/cfg/xymonapi-agent/agents/bad.toml"

# A coordinator: ops over xymon and backup.
cat > "$work/stub/opencode" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$work/opencode.args"
cp "\$OPENCODE_CONFIG" "$work/opencode.json"
env | grep '^XYMONAPI_AGENT' > "$work/opencode.env" || true
echo "an answer"
STUB
cat > "$work/cfg/xymonapi-agent/agents/ops.toml" <<'PROF'
description = "routes a question to the right agent"
backend = ["claude"]
agents = ["xymon", "backup"]
PROF
out=$(run agents)
assert_contains "mcp agents; agents xymon, backup" "$out" "agents shows a coordinator's agents, and its tools server"
out=$(run --agent ops ask "anything wrong overnight?")
assert_equal "xymon 4.3.31" "$out" "a coordinator is asked like any agent"
args=$(cat "$work/claude.args")
assert_contains "xymonapi-agent/xymonapi-agent.sh" "$args" "its backend gets this command as an MCP server"
assert_contains "mcp-agents" "$args" "serving the agents"
assert_contains "mcp__agents__*" "$args" "and may call only those tools"
assert_contains "You coordinate other agents" "$args" "with the coordinator's prompt"
grep -q 'mcp__xymon__' "$work/claude.args" && fail "a coordinator without the xymon server was allowed its tools"

# The MCP server itself: its tools, an ask of backup run as backup, with
# backup's backend, not the parent's; the guards.
mcp() { printf '%s\n' "$@" | XYMONAPI_AGENT_BACKEND=claude PATH="$path" "$agent" --agent ops mcp-agents; }
init='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}'
list='{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
call='{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ask_backup","arguments":{"question":"did it run?"}}}'
out=$(mcp "$init" "$list" "$call")
assert_contains '"serverInfo":{"name":"agents"' "$out" "mcp-agents answers initialize"
assert_contains '"name":"ask_xymon","description":"Ask the agent xymon: the Xymon board' "$out" "lists one tool per agent, with its description"
assert_contains '"name":"ask_backup"' "$out" "each of them"
assert_contains '"id":3,"result":{"content":[{"type":"text","text":"an answer"}],"isError":false}' "$out" "and an ask_NAME call answers with that agent's answer"
assert_contains '"restic_*": "allow"' "$(cat "$work/opencode.json")" "the child ran as backup, with backup's backend and tools"
assert_equal "XYMONAPI_AGENT_DEPTH=1" "$(cat "$work/opencode.env")" "one deeper, and without the parent's backend choice"
out=$(mcp '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"ask_nobody","arguments":{"question":"x"}}}')
assert_contains '"isError":true' "$out" "a tool that is not an agent is an error"
out=$(printf '%s\n' "$call" | XYMONAPI_AGENT_DEPTH=0 PATH="$path" "$agent" --agent ops mcp-agents)
assert_contains "the depth limit is reached" "$out" "at depth 0 an ask is refused"
out=$(printf '%s\n' "$call" "$call" | XYMONAPI_AGENT_SUBASKS=1 PATH="$path" "$agent" --agent ops mcp-agents)
assert_contains '"id":3,"result":{"content":[{"type":"text","text":"an answer"}]' "$out" "the first ask within the cap answers"
assert_contains "asked its agents 1 times already" "$out" "the one past it is refused"
rc=0; out=$(run --agent xymon mcp-agents 2>&1 </dev/null) || rc=$?
assert_contains "coordinates no agents" "$out" "mcp-agents for an agent with none says so"

# A coordinator naming itself, or an agent not defined, is refused.
printf 'agents = ["loop"]\n' > "$work/cfg/xymonapi-agent/agents/loop.toml"
rc=0; out=$(run agents 2>&1) || rc=$?
assert_contains "names the agent itself" "$out" "a profile in its own agents list is refused"
printf 'agents = ["nosuch"]\n' > "$work/cfg/xymonapi-agent/agents/loop.toml"
rc=0; out=$(run agents 2>&1) || rc=$?
assert_contains "names 'nosuch', which no profile defines" "$out" "an agent that is not defined is refused"
rm "$work/cfg/xymonapi-agent/agents/loop.toml"

pass "xymonapi-agent runs the chosen agent CLI with the agent's MCP servers as its only tools, tries the backends of a profile in order, serves a coordinator's agents as tools with the two guards, continues a Claude Code session by name, and doctor tells a tool's answer from any other"
