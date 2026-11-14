# SPDX-License-Identifier: GPL-2.0-or-later
"""HTTP server for the Xymon API.

Only the operations implemented here are registered; any other path answers
404. The OpenAPI document served at /openapi.json is openapi.yaml, beside
this file, so what a client reads is what the server does.

Started by xymonapi.sh, which checks Python and the modules first.
"""
from __future__ import annotations

import argparse
import asyncio
import collections
import contextlib
import contextvars
import io
import json
import logging
import os
import re
import secrets
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tarfile
import time
from pathlib import Path

import yaml
from fastapi import FastAPI
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse, Response

import tokens
import xymon

# The request a log line is about, given to the client as X-Request-Id
# (openapi.yaml, C5); "-" for a line about no request.
REQUEST_ID: contextvars.ContextVar[str] = contextvars.ContextVar("request_id", default="-")
_REQUEST_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")


class _WithRequestId(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = REQUEST_ID.get()
        return True


# To stderr, which the task's LOGFILE collects: $XYMONSERVERLOGS/xymonapi.log.
logging.basicConfig(stream=sys.stderr, level=logging.INFO,
                    format="%(asctime)s %(levelname)s [%(request_id)s] %(message)s")
for _handler in logging.getLogger().handlers:
    _handler.addFilter(_WithRequestId())
log = logging.getLogger("xymonapi")

SPEC_PATH = Path(__file__).resolve().parent / "openapi.yaml"
RAG_DIR = Path(__file__).resolve().parent.parent / "xymonapi-rag"


def _rag():
    """xymonapi-rag/xymonrag.py, beside this plugin, imported when first needed: /search and the search
    part of /health use it, the other operations do not, and its modules
    (fastembed, numpy) are not required unless the search is used."""
    if str(RAG_DIR) not in sys.path:
        sys.path.insert(0, str(RAG_DIR))
    import xymonrag
    return xymonrag


def _upstream(exc: Exception) -> JSONResponse:
    """502. xymon.Upstream carries a text of this program's own; anything
    else -- a program's stderr, a traceback -- names paths and settings a
    stranger need not see, so it goes to the log and the answer says where."""
    if isinstance(exc, xymon.Upstream):
        return JSONResponse({"error": "upstream", "detail": str(exc)}, status_code=502)
    log.error("%s: %s", type(exc).__name__, exc)
    return JSONResponse({"error": "upstream",
                         "detail": "the server could not answer; the reason is in xymonapi.log"},
                        status_code=502)


def _refused(exc: Exception) -> JSONResponse:
    """The answer for an exception: 400, 404 or 502."""
    if isinstance(exc, xymon.BadRequest):
        return JSONResponse({"error": "bad_request", "detail": str(exc)}, status_code=400)
    if isinstance(exc, xymon.NotFound):
        return JSONResponse({"error": "not_found", "detail": str(exc)}, status_code=404)
    return _upstream(exc)


# The handlers are plain functions, not coroutines: Starlette runs them in
# its thread pool, so a slow xymond, rrdtool or showgraph holds up that one
# request and not the event loop -- /health keeps answering meanwhile.
def _health(request):
    out: dict = {"alive": False, "search": _search_info()}
    # The version of the code this process runs, which a client compares
    # with its own: here, behind the password.
    version = VERSION
    if version:
        out["version"] = version
    try:
        version = xymon.ping()
    except Exception as exc:                        # noqa: BLE001
        log.warning("ping: %s: %s", type(exc).__name__, exc)
        return JSONResponse(out)
    out.update(alive=True, server_version=version)
    return JSONResponse(out)


def _search_info():
    """The index /search reads, for /health: its size and age, or null when
    there is none -- or no numpy to read it with, which the log says."""
    try:
        return _rag().index_info()
    except Exception as exc:                        # noqa: BLE001
        log.warning("search index: %s: %s", type(exc).__name__, exc)
        return None


def _search(request):
    q = request.query_params
    question, kind, k = (q.get("q") or "").strip(), q.get("kind"), q.get("k", "5")
    if not question:
        return JSONResponse({"error": "bad_request", "detail": "q, the question, is needed"},
                            status_code=400)
    if kind is not None and kind not in ("docs", "history"):
        return JSONResponse({"error": "bad_request", "detail": "kind must be docs or history"},
                            status_code=400)
    if not k.isdigit() or not 1 <= int(k) <= 20:
        return JSONResponse({"error": "bad_request", "detail": "k must be 1 to 20"},
                            status_code=400)
    try:
        rag = _rag()
    except ImportError as exc:
        return JSONResponse({"error": "not_found", "detail": "search is not set up on this "
                             "server: the Python modules in xymonapi-rag/requirements.txt are missing "
                             f"({exc.name})"}, status_code=404)
    try:
        # remote=False: this is the server; with no index it says so rather
        # than asking itself.
        items = rag.search(question[:2000], kind, int(k), remote=False)
    except rag.IndexProblem as exc:
        return JSONResponse({"error": "not_found", "detail": f"search is not set up on this "
                             f"server: {exc}; enable the xymonapi-rag task"}, status_code=404)
    except Exception as exc:                        # noqa: BLE001
        return _upstream(exc)
    return JSONResponse({"items": items})


def _states(request):
    q = request.query_params
    try:
        items = xymon.states(q.get("entity"), q.get("test"), q.get("verdict"))
    except Exception as exc:                        # noqa: BLE001
        return _upstream(exc)
    return JSONResponse({"items": items})


def _alarms(request):
    try:
        items = xymon.alarms()
    except Exception as exc:                        # noqa: BLE001
        return _upstream(exc)
    return JSONResponse({"items": items})


def _entities(request):
    try:
        items = xymon.entities()
    except Exception as exc:                        # noqa: BLE001
        return _upstream(exc)
    return JSONResponse({"items": items})


def _pages(request):
    try:
        tree = xymon.pages()
    except Exception as exc:                        # noqa: BLE001
        return _upstream(exc)
    return JSONResponse(tree)


def _status(request):
    q = request.query_params
    try:
        s = xymon.status(q.get("entity"), q.get("test"))
    except Exception as exc:                        # noqa: BLE001
        return _refused(exc)
    return JSONResponse(s)


def _series(request):
    q = request.query_params
    try:
        s = xymon.series(q.get("entity"), q.get("test"), q.get("metric"),
                         q.get("from", "-24h"), q.get("to", "now"))
    except Exception as exc:                        # noqa: BLE001
        return _refused(exc)
    return JSONResponse({"series": [s]})


def _graphs(request):
    q = request.query_params
    try:
        png = xymon.graph(q.get("entity"), q.get("test"),
                          q.get("from", "-24h"), q.get("to", "now"))
    except Exception as exc:                        # noqa: BLE001
        return _refused(exc)
    return Response(content=png, media_type="image/png")


def _events(request):
    q = request.query_params
    try:
        items = xymon.events(q.get("entity"), q.get("test"), q.get("since"), q.get("limit"),
                             q.get("before"))
    except Exception as exc:                        # noqa: BLE001
        return _refused(exc)
    return JSONResponse({"items": items})


def _histlog(request):
    q = request.query_params
    try:
        log = xymon.histlog(q.get("entity"), q.get("test"), q.get("time"))
    except Exception as exc:                        # noqa: BLE001
        return _refused(exc)
    return JSONResponse(log)


HERE = Path(__file__).resolve().parent
_VERSION_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,127}")
# What each plugin's install stages for other machines to install from:
# its directory, as in the repository, beside install.sh and LICENSE. Not under this plugin's own directory, which an install empties.
DIST = HERE.parent / "xymon-plugins-dist"


def installed_version() -> str:
    """The version in the VERSION file beside this plugin, or ""."""
    try:
        ref = (HERE / "VERSION").read_text(encoding="ascii").strip()
    except (OSError, UnicodeDecodeError):
        return ""
    return ref if _VERSION_RE.fullmatch(ref) else ""


# Read once, when the process starts: /health reports the code that runs,
# not an install it has not been restarted for, whose VERSION is beside it.
VERSION = installed_version()


def _plugins(request):
    """The code of the plugins installed here, as staged for other machines,
    in a .tar.gz rooted at xymon-plugins/: what a machine runs
    ./install.sh install-tools in, at this server's versions. Open to anyone, as the
    repository is: it holds no setting and nothing secret. Which plugins it
    holds is whatever is staged; this API names none."""
    plugins = DIST / "plugins"
    if not plugins.is_dir() or not any(plugins.iterdir()):
        return JSONResponse({"error": "not_found",
                             "detail": "no plugin's code is staged on this server: ./install.sh "
                                       "install-server there stages it"}, status_code=404)

    def neutral(info: tarfile.TarInfo) -> tarfile.TarInfo:
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        return info

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        tar.add(DIST, arcname="xymon-plugins", filter=neutral)
    return Response(content=buf.getvalue(), media_type="application/gzip",
                    headers={"Content-Disposition": 'attachment; filename="xymon-plugins.tar.gz"'})


def _no_users() -> JSONResponse | None:
    if xymon.XYMONAPI_PASSWD:
        return None
    return JSONResponse({"error": "bad_request", "detail": "tokens are for the users of "
                         "XYMONAPI_PASSWD, and this API asks for no password"}, status_code=400)


async def _tokens(request):
    """GET: the caller's tokens. POST {"client": NAME}: a new token for the
    caller on that machine, replacing any it had, shown this once."""
    refused = _no_users()
    if refused:
        return refused
    user = request.state.user
    if request.method == "GET":
        return JSONResponse({"items": await run_in_threadpool(tokens.listing, user)})
    try:
        body = await request.json()
        client = tokens.valid_client(body.get("client") if isinstance(body, dict) else None)
    except ValueError as exc:
        return JSONResponse({"error": "bad_request", "detail": str(exc)}, status_code=400)
    try:
        token = await run_in_threadpool(tokens.issue, user, client)
    except OSError as exc:
        return _upstream(RuntimeError(f"cannot write {tokens.TOKENS_FILE}: {exc.strerror}"))
    log.info("token issued to %s@%s", user, client)
    return JSONResponse({"user": user, "client": client, "token": token}, status_code=201)


async def _token(request):
    """DELETE: revoke the caller's token on one machine."""
    refused = _no_users()
    if refused:
        return refused
    user, client = request.state.user, request.path_params["client"]
    try:
        gone = await run_in_threadpool(tokens.revoke, user, client)
    except ValueError as exc:
        return JSONResponse({"error": "bad_request", "detail": str(exc)}, status_code=400)
    except OSError as exc:
        return _upstream(RuntimeError(f"cannot write {tokens.TOKENS_FILE}: {exc.strerror}"))
    if not gone:
        return JSONResponse({"error": "not_found", "detail": f"{user} has no token on {client}"},
                            status_code=404)
    log.info("token of %s@%s revoked", user, client)
    return Response(status_code=204)


# /ask: a question for xymonapi-agent, installed beside the API, which runs
# an agent CLI with the Xymon MCP server as its tool and answers in words
# (openapi.yaml, C6 to C8). Off unless XYMONAPI_ASK is set: a question costs
# money and time where a GET does not, and the agent CLI is the admin's to
# install and log in, as the Xymon user.
ASK = os.environ.get("XYMONAPI_ASK", "") not in ("", "0", "no", "off", "false")
ASK_PER_HOUR = int(os.environ.get("XYMONAPI_ASK_PER_HOUR", "60") or 0)
ASK_TIMEOUT = float(os.environ.get("XYMONAPI_ASK_TIMEOUT", "300"))
ASK_MAX = int(os.environ.get("XYMONAPI_ASK_MAX", "2000"))
AGENT = HERE.parent / "xymonapi-agent" / "xymonapi-agent.sh"
_ASK_NAME = re.compile(r"[A-Za-z0-9._-]{1,64}")
# Per caller: the lock that makes it one question at a time, and when the
# last hour's questions were asked (C8). In this process only; the task
# runs one.
_ask_locks: dict[str, asyncio.Lock] = {}
_ask_times: dict[str, collections.deque] = collections.defaultdict(collections.deque)


def _ask_agent(question: str, agent: str, session: str) -> dict:
    """Run xymonapi-agent for one question, as this process's user, with
    this environment: on the server, the client finds the API's own socket
    from it (XYMONAPI_SOCKET, XYMONVAR), so nothing crosses the network.
    The agent's JSON, or RuntimeError with the agent's last line."""
    argv = [str(AGENT), "--agent", agent, "ask", "--json", question]
    if session:
        argv += ["--session", session]
    env = {k: v for k, v in os.environ.items() if k != "XYMONAPI_URL"}
    env["XYMONAPI_AGENT_TIMEOUT"] = str(ASK_TIMEOUT)
    try:
        r = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=ASK_TIMEOUT + 5)
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"the agent gave no answer in {ASK_TIMEOUT:g} seconds "
                           "(XYMONAPI_ASK_TIMEOUT)") from None
    if r.returncode != 0:
        lines = (r.stderr or r.stdout).strip().splitlines() or ["no message"]
        raise RuntimeError(lines[-1].replace("xymonapi-agent: ", "", 1))
    try:
        out = json.loads(r.stdout)
        return {"answer": str(out["answer"]), "agent": str(out["agent"]),
                "backend": str(out["backend"])}
    except (ValueError, KeyError, TypeError):
        raise RuntimeError("the agent gave no readable answer") from None


async def _ask(request):
    """POST {"question": Q, "session": NAME?, "agent": NAME?}: the agent's
    answer, in words, with which agent and backend gave it."""
    if not ASK:
        # As a path this server does not have (C2): a server that has not
        # opted in shows nothing of the feature.
        return JSONResponse({"error": "not_found", "detail": "Not Found"}, status_code=404)
    if not AGENT.is_file():
        return JSONResponse({"error": "not_found", "detail": "XYMONAPI_ASK is set, but "
                             "xymonapi-agent is not installed beside the API: "
                             "./install.sh install-server xymonapi-agent"}, status_code=404)
    try:
        body = await request.json()
    except ValueError:
        body = None
    if not isinstance(body, dict):
        return JSONResponse({"error": "bad_request", "detail": "the body is a JSON object with "
                             "question, and session and agent if wanted"}, status_code=400)
    question = body.get("question")
    if not isinstance(question, str) or not question.strip():
        return JSONResponse({"error": "bad_request", "detail": "question, in words, is needed"},
                            status_code=400)
    if len(question) > ASK_MAX:
        return JSONResponse({"error": "bad_request", "detail": f"question is longer than "
                             f"{ASK_MAX} characters (XYMONAPI_ASK_MAX)"}, status_code=400)
    session, agent = body.get("session", ""), body.get("agent", "xymon")
    for what, v in (("session", session), ("agent", agent)):
        if not isinstance(v, str) or (v and not _ASK_NAME.fullmatch(v)):
            return JSONResponse({"error": "bad_request", "detail": f"{what} is 1 to 64 letters, "
                                 "digits, dots, underscores or hyphens"}, status_code=400)
    if not agent:
        agent = "xymon"
    # Who asks: user and machine from the token, user alone from a password,
    # local from the socket. A session is theirs: prefixed with it, so that
    # no other caller can continue it (C7).
    user = getattr(request.state, "user", "") or "local"
    client = getattr(request.state, "client", None) or ("local" if user == "local" else "password")
    caller = f"{user}@{client}"
    if session:
        session = f"{caller}:{session}"

    lock = _ask_locks.setdefault(caller, asyncio.Lock())
    if lock.locked():
        return JSONResponse({"error": "too_many", "detail": f"{caller} has a question being "
                             "answered; one at a time"}, status_code=429,
                            headers={"Retry-After": "10"})
    times = _ask_times[caller]
    now = time.monotonic()
    while times and times[0] <= now - 3600:
        times.popleft()
    if ASK_PER_HOUR and len(times) >= ASK_PER_HOUR:
        wait = int(times[0] + 3600 - now) + 1
        return JSONResponse({"error": "too_many", "detail": f"{caller} has asked {ASK_PER_HOUR} "
                             "questions this hour, the most allowed (XYMONAPI_ASK_PER_HOUR)"},
                            status_code=429, headers={"Retry-After": str(wait)})
    times.append(now)
    async with lock:
        log.info("ask by %s: agent %s%s", caller, agent, f", session {session}" if session else "")
        started = time.monotonic()
        try:
            out = await run_in_threadpool(_ask_agent, question, agent, session)
        except RuntimeError as exc:
            log.warning("ask by %s failed after %.0fs: %s", caller, time.monotonic() - started, exc)
            return JSONResponse({"error": "upstream", "detail": f"xymonapi-agent: {exc}"},
                                status_code=502)
        log.info("ask by %s answered by %s/%s in %.0fs", caller, out["agent"], out["backend"],
                 time.monotonic() - started)
    if session:
        out["session"] = body.get("session")
    return JSONResponse(out)


ROUTES = {
    "/health": _health,
    "/states": _states,
    "/alarms": _alarms,
    "/entities": _entities,
    "/pages": _pages,
    "/status": _status,
    "/series": _series,
    "/graphs": _graphs,
    "/events": _events,
    "/histlog": _histlog,
    "/search": _search,
    "/plugins": _plugins,
}


def build_app() -> FastAPI:
    if not xymon.XYMSRV:
        sys.exit("xymonapi: XYMSRV is not set; start it from xymonlaunch with "
                 "ENVFILE, or through xymoncmd")
    spec = yaml.safe_load(SPEC_PATH.read_text())
    base = spec["servers"][0]["url"].rstrip("/")
    app = FastAPI(title=spec["info"]["title"], version=spec["info"]["version"])

    # A path that is none of ours, or a method a path does not take, is
    # answered by the framework with {"detail": ...}: put in the spec's form,
    # an error of its closed list (openapi.yaml, C1 and C2).
    @app.exception_handler(HTTPException)
    async def _framework_error(request, exc):
        error = {400: "bad_request", 401: "unauthorized", 404: "not_found",
                 405: "method_not_allowed"}.get(exc.status_code, "bad_request")
        return JSONResponse({"error": error, "detail": str(exc.detail)},
                            status_code=exc.status_code, headers=exc.headers)

    try:
        n = xymon.load_hide()
    except OSError as exc:
        sys.exit(f"xymonapi: cannot read XYMONAPI_HIDE={xymon.HIDE_FILE}: {exc.strerror}")
    except ValueError as exc:
        sys.exit(f"xymonapi: XYMONAPI_HIDE: {exc} is not a regular expression")
    if n:
        log.info("hiding what %d expression(s) of %s match", n, xymon.HIDE_FILE)
    if ASK:
        if AGENT.is_file():
            log.info("/ask is on: xymonapi-agent at %s, %d an hour per caller, %gs each",
                     AGENT, ASK_PER_HOUR, ASK_TIMEOUT)
        else:
            log.warning("XYMONAPI_ASK is set, but xymonapi-agent is not at %s: /ask will say so", AGENT)

    if xymon.XYMONAPI_PASSWD:
        # Refuse to start rather than answer 401 to everyone, which looks
        # like a wrong password when it is a wrong setting.
        if not os.access(xymon.XYMONAPI_PASSWD, os.R_OK):
            if "XYMONAPI_PASSWD" not in os.environ:
                sys.exit(f"xymonapi: XYMONAPI_PASSWD is not set, and Xymon's password file, "
                         f"{xymon.XYMONAPI_PASSWD}, cannot be read: create it with htpasswd, name "
                         f"another in XYMONAPI_PASSWD, or set XYMONAPI_PASSWD empty for an API "
                         f"open to anyone who reaches it")
            sys.exit(f"xymonapi: cannot read XYMONAPI_PASSWD={xymon.XYMONAPI_PASSWD}")
        if shutil.which("htpasswd") is None:
            sys.exit("xymonapi: XYMONAPI_PASSWD is set, and checking it needs "
                     "Apache's htpasswd, which is not on PATH")

        # Every path, not only the API's: FastAPI also serves /openapi.json
        # and its /docs pages, and with a password set nothing is answered
        # to a stranger but /plugins, the plugins' code.
        def refuse(detail: str) -> JSONResponse:
            return JSONResponse({"error": "unauthorized", "detail": detail}, status_code=401,
                                headers={"WWW-Authenticate": 'Basic realm="xymon"'})

        @app.middleware("http")
        async def _auth(request, call_next):
            # /plugins alone is open: the code it gives is the repository's,
            # and a machine fetches it before it has a token to send.
            if request.url.path == base + "/plugins":
                return await call_next(request)
            # A request through the Unix socket (XYMONAPI_SOCKET) is from a
            # user the socket's permissions let in -- the kernel checked
            # that, which no header could -- so it needs no password. Not
            # for the token operations, which say who the caller is: those
            # take the password, as a token does not either.
            if request.scope.get("xymonapi_local"):
                if request.url.path.startswith(base + "/tokens"):
                    return refuse("tokens are managed with the user's password, not through the socket")
                request.state.user, request.state.client = "local", None
                return await call_next(request)
            header = request.headers.get("authorization") or ""
            if header.startswith("Bearer "):
                # A token opens every path but the token operations: it may
                # not make or list tokens, or a stolen one would renew itself.
                if request.url.path.startswith(base + "/tokens"):
                    return refuse("tokens are managed with the user's password, not a token")
                who = await run_in_threadpool(tokens.check, header[7:].strip())
                if not who:
                    return refuse("this token is not valid, or was revoked")
                # The owner must still be a user: removing one from the
                # password file ends their tokens too, with no second step.
                # They are deleted, not only refused, so that a person given
                # the name later does not inherit the machines. A file that
                # cannot be read says nothing of the user: refused, kept.
                known = xymon.has_user(who[0])
                if known is None:
                    return refuse("the password file cannot be read")
                if not known:
                    n = await run_in_threadpool(tokens.revoke_user, who[0])
                    log.info("%s is no longer in the password file: %d token(s) revoked", who[0], n)
                    return refuse(f"the user {who[0]} of this token is no longer in the password file; "
                                  "their tokens are revoked")
                request.state.user, request.state.client = who
                log.info("%s@%s %s %s", who[0], who[1], request.method, request.url.path)
                return await call_next(request)
            creds = xymon.parse_basic(header)
            # htpasswd checks a bcrypt hash in tens of milliseconds: off the loop.
            if not creds or not await run_in_threadpool(xymon.verify_basic, *creds):
                return refuse("a user and password, or a client token, are needed")
            request.state.user, request.state.client = creds[0], None
            return await call_next(request)

    for path, handler in ROUTES.items():
        app.add_route(base + path, handler, methods=["GET"])
    app.add_route(base + "/ask", _ask, methods=["POST"])
    app.add_route(base + "/tokens", _tokens, methods=["GET", "POST"])
    app.add_route(base + "/tokens/{client}", _token, methods=["DELETE"])
    app.openapi = lambda: spec                      # type: ignore[assignment]

    # Added last, so outermost: every answer gets its X-Request-Id, a refusal
    # of the password check and a framework 404 or 405 included, and every log
    # line about the request carries it (C5). A failure is logged once with
    # it, so that what a client was told can be found here.
    @app.middleware("http")
    async def _request_id(request, call_next):
        rid = request.headers.get("x-request-id", "")
        if not _REQUEST_ID.fullmatch(rid):
            rid = secrets.token_hex(8)
        reset = REQUEST_ID.set(rid)
        try:
            response = await call_next(request)
            if response.status_code >= 400:
                log.info("%s %s answered %d", request.method, request.url.path, response.status_code)
        finally:
            REQUEST_ID.reset(reset)
        response.headers["X-Request-Id"] = rid
        return response

    return app


app = build_app()


async def _local_app(scope, receive, send):
    """The app as the Unix socket serves it: each request marked as local, which
    the password check above reads. The mark is put here, by the listener, so
    that nothing a client sends can carry it."""
    if scope["type"] == "http":
        scope = dict(scope, xymonapi_local=True)
    await app(scope, receive, send)


def main(argv: list[str]) -> int:
    """Serve the app on the address given and, with --socket, on a Unix socket
    too: one process, two listeners, so that the socket's requests are told
    apart by where they came in, and TLS, when on, is the port's alone."""
    import uvicorn

    ap = argparse.ArgumentParser(prog="xymonapi")
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=1986)
    ap.add_argument("--socket", default="")
    ap.add_argument("--ssl-certfile")
    ap.add_argument("--ssl-keyfile")
    args = ap.parse_args(argv)

    class Server(uvicorn.Server):
        # uvicorn's serve() takes the process's signals for itself and gives
        # them back when done; with two servers in one loop the second would
        # take them from the first. Neither takes them: one handler, below,
        # stops both.
        @contextlib.contextmanager
        def capture_signals(self):
            yield

    servers: list[tuple[Server, socket.socket]] = []
    try:
        tcp = socket.create_server((args.host, args.port),
                                   family=socket.AF_INET6 if ":" in args.host else socket.AF_INET)
    except OSError as e:
        sys.exit(f"xymonapi: cannot listen on {args.host}:{args.port}: {(e.strerror or str(e)).lower()}")
    servers.append((Server(uvicorn.Config(app, access_log=False, ssl_certfile=args.ssl_certfile,
                                          ssl_keyfile=args.ssl_keyfile)), tcp))
    if args.socket:
        # Mode 660 in a directory of 750: the Xymon user and its group reach
        # it, and nobody else (xymonapi(8), XYMONAPI_SOCKET). A file left by
        # an earlier run is replaced; another live server there is not
        # checked for, as the port's "address in use" is: the task runs one.
        d = os.path.dirname(args.socket)
        if d:
            os.makedirs(d, mode=0o750, exist_ok=True)
        with contextlib.suppress(FileNotFoundError):
            if stat.S_ISSOCK(os.lstat(args.socket).st_mode):
                os.unlink(args.socket)
        uds = socket.socket(socket.AF_UNIX)
        uds.bind(args.socket)
        os.chmod(args.socket, 0o660)
        uds.listen(128)
        servers.append((Server(uvicorn.Config(_local_app, access_log=False)), uds))
        log.info("listening on the socket %s too, with no password asked there", args.socket)

    def stop(sig, frame):
        for server, _ in servers:
            server.handle_exit(sig, frame)
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, stop)

    async def serve():
        await asyncio.gather(*(server.serve(sockets=[sock]) for server, sock in servers))
    try:
        asyncio.run(serve())
    finally:
        if args.socket:
            with contextlib.suppress(OSError):
                os.unlink(args.socket)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
