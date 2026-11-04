# SPDX-License-Identifier: GPL-2.0-or-later
"""A client for xymonapi(8), with nothing but the standard library: the MCP
server and the search in xymonapi-rag/ both read the API through it.

XYMONAPI_URL is where the API is: http:// or https://, or unix:PATH, the
API's own Unix socket on the server, where no credential is needed because
the socket's permissions already say who may connect. Unset, it is that
socket, XYMONAPI_SOCKET or $XYMONVAR/xymonapi/api.sock, when the file is
there -- the plugins' tasks on the server have both settings -- and
http://127.0.0.1:1986 otherwise.
XYMONAPI_TOKEN_FILE names a file holding a client token -- the one
xymonapi-connect(1) keeps -- sent when the API asks for a user: the token
is this machine's own, revoked on its own (xymonapi(8), TOKENS). It is the
only credential sent: a password is never kept here. XYMONAPI_TOKEN is the
token itself, for a test or a one-off.
XYMONAPI_CA names the certificate, or the CA, to trust for an https:// URL
when it is not one the system trusts already: xymond's own, from
xymon-tls(7), which the API uses too.

Run as a program, it is xymonapi-connect(1): `xymonapi_client.py connect
URL [NAME]` connects this machine to the API at URL.
"""
from __future__ import annotations

import base64
import getpass
import http.client
import json
import os
import re
import secrets
import shlex
import socket
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote, unquote, urlencode, urlsplit


def _default_url() -> str:
    sock = os.environ.get("XYMONAPI_SOCKET") or (
        os.path.join(os.environ["XYMONVAR"], "xymonapi", "api.sock") if os.environ.get("XYMONVAR") else "")
    return f"unix:{sock}" if sock and os.path.exists(sock) else "http://127.0.0.1:1986"


URL = (os.environ.get("XYMONAPI_URL") or _default_url()).rstrip("/")
CA = os.environ.get("XYMONAPI_CA", "")
TOKEN = os.environ.get("XYMONAPI_TOKEN", "")
TOKEN_FILE = os.environ.get("XYMONAPI_TOKEN_FILE", "")


def _token() -> str:
    """XYMONAPI_TOKEN, or the first line of XYMONAPI_TOKEN_FILE, or ""."""
    if TOKEN or not TOKEN_FILE:
        return TOKEN
    try:
        with open(TOKEN_FILE, encoding="utf-8") as fd:
            return fd.readline().strip()
    except OSError as e:
        raise APIError(f"cannot read XYMONAPI_TOKEN_FILE={TOKEN_FILE}: {e.strerror}") from e


class APIError(RuntimeError):
    """The API could not be reached, or refused the request; the text says which.
    status is the HTTP status of a refusal, None when there was no answer."""

    def __init__(self, message: str, status: int | None = None):
        super().__init__(message)
        self.status = status


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    # urllib follows a redirect with every header but the content ones, so the
    # Authorization header would go to whatever host a redirect names. The
    # API never redirects; a redirect is answered as the error it is.
    def redirect_request(self, *args, **kwargs):
        return None


def _context() -> ssl.SSLContext:
    """Full verification, against XYMONAPI_CA when set, the system's store
    otherwise. Never less: the token rides on this connection."""
    ctx = ssl.create_default_context()
    if CA:
        try:
            ctx.load_verify_locations(CA)
        except (OSError, ssl.SSLError) as e:
            raise APIError(f"cannot use XYMONAPI_CA={CA}: {e}") from e
    return ctx


class _UnixConnection(http.client.HTTPConnection):
    """HTTP over a Unix socket: the path, percent-encoded, stands where a
    host would in the URL, unix://%2Fvar%2F...%2Fapi.sock/xymon/api/v1/..."""

    def __init__(self, host: str, timeout=None, **kwargs):
        super().__init__("localhost", timeout=timeout, **kwargs)
        self.path = unquote(host)

    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


class _UnixHandler(urllib.request.AbstractHTTPHandler):
    def unix_open(self, req):
        req.add_unredirected_header("Host", "localhost")
        return self.do_open(_UnixConnection, req)

    unix_request = urllib.request.AbstractHTTPHandler.do_request_


def _url(path: str) -> str:
    """The full URL of PATH under /xymon/api/v1 at URL, in the form the opener
    takes: as given for http(s), the socket's path encoded as the host for
    unix:PATH (or unix:///PATH)."""
    parts = urlsplit(URL)
    if parts.scheme == "unix":
        return f"unix://{quote(parts.path, safe='')}/xymon/api/v1{path}"
    return f"{URL}/xymon/api/v1{path}"


_opener: urllib.request.OpenerDirector | None = None


def open_url(req, timeout: float):
    """urlopen through the opener above: no redirect, full verification. The
    opener is built on the first call, not when the module is imported, so
    that a wrong XYMONAPI_CA is an APIError each tool and command reports,
    rather than a crash before the MCP server has answered anything."""
    global _opener
    if _opener is None:
        _opener = urllib.request.build_opener(
            _NoRedirect, urllib.request.HTTPSHandler(context=_context()), _UnixHandler)
    return _opener.open(req, timeout=timeout)


# The xymonapi version this client was written for, the floor in the PLUGIN
# file beside this one; tests/api/xymonapi-auth.sh checks the two agree.
# The API keeps its answers within a major version, so a newer one is fine.
API_FLOOR = "0.1.0"
_TRIPLE = re.compile(r"(\d+)\.(\d+)\.(\d+)")
_warning: str | None = None


def _triple(version: str) -> tuple[int, int, int] | None:
    m = _TRIPLE.search(version)
    return (int(m[1]), int(m[2]), int(m[3])) if m else None


def version_warning() -> str:
    """What to do when the API is older than this client was written for,
    asked of /health once per process; "" when it is not, or does not say
    its version (a server from before it did), or does not answer. Nothing
    is updated from here: the server's admin does that."""
    global _warning
    if _warning is None:
        _warning = ""
        try:
            theirs = api("/health").get("version", "")
        except APIError:
            return _warning
        t = _triple(theirs)
        if t and t < _triple(API_FLOOR):
            _warning = (f"the API at {URL} is xymonapi {theirs}; this client needs {API_FLOOR} or later: "
                        "./install.sh install on the server, from a newer checkout of xymon-plugins, brings it up to date")
            # Once, on stderr, which an MCP client logs: stdout is the protocol.
            print(f"xymonapi: {_warning}", file=sys.stderr)
    return _warning


# An answer of the API is a board or a list of events: never near this.
MAX_BODY = 16 * 1024 * 1024


def api(path: str, **params: str | None) -> dict:
    """GET PATH under /xymon/api/v1 and return the JSON it answers."""
    # http, https and the API's own socket: urllib also reads file:// and ftp:// URLs.
    if urlsplit(URL).scheme not in ("http", "https", "unix"):
        raise APIError(f"XYMONAPI_URL must be an http:// or https:// URL, or unix:PATH, not {URL!r}")
    # Left out when not given; "0" is a value.
    query = urlencode({k: v for k, v in params.items() if v is not None and v != ""})
    # This call's identifier, which the API logs and sends back: an error
    # says it, so that the API's log line about it can be found.
    rid = secrets.token_hex(8)
    try:
        req = urllib.request.Request(_url(path) + (f"?{query}" if query else ""),
                                     headers={"X-Request-Id": rid})
        bearer = _token()
        if bearer:
            req.add_header("Authorization", f"Bearer {bearer}")
        with open_url(req, 30) as r:
            body = r.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            raise APIError(f"xymonapi at {URL} answered more than {MAX_BODY} bytes")
        return json.loads(body)
    except urllib.error.HTTPError as e:
        # The API's own explanation, not a bare status; and for the two
        # failures of a first setup, what to check.
        detail = e.read().decode(errors="replace")
        if e.code == 401:
            detail += (" -- the token in XYMONAPI_TOKEN_FILE was revoked or replaced: run "
                       "xymonapi-connect again" if (TOKEN or TOKEN_FILE) else
                       " -- set XYMONAPI_TOKEN_FILE: xymonapi-connect gets this machine a "
                       "token and writes it")
        rid = e.headers.get("X-Request-Id", rid) if e.headers else rid
        raise APIError(f"xymonapi answered {e.code}: {detail} (request id {rid})", e.code) from e
    except urllib.error.URLError as e:
        if isinstance(e.reason, ssl.SSLCertVerificationError):
            raise APIError(f"xymonapi at {URL} has a certificate this machine does not trust: "
                           f"{e.reason.verify_message} -- name the server's certificate, or the "
                           "CA that signed it, in XYMONAPI_CA") from e
        if urlsplit(URL).scheme == "unix":
            raise APIError(f"cannot reach xymonapi at {URL}: {e.reason} -- is the API running, with "
                           "that socket (XYMONAPI_SOCKET), and may this user connect to it?") from e
        raise APIError(f"cannot reach xymonapi at {URL}: {e.reason} -- is the API running, and "
                       "XYMONAPI_URL right? From another machine it is reached over HTTPS, "
                       "as xymonapi(8) says") from e
    except ValueError as e:              # a URL urllib cannot use, or an answer that is not JSON
        raise APIError(f"xymonapi at {URL}: {e}") from e
    except OSError as e:                 # the connection broke, or timed out, while reading
        raise APIError(f"xymonapi at {URL}: {e}") from e


# xymonapi-connect(1): this machine's token for the API at URL, asked for
# once with a user's password, which is not kept. What a client needs then
# is printed, as shell settings.

def _say(msg: str) -> None:
    print(f"xymonapi-connect: {msg}", file=sys.stderr)


def _machine() -> str:
    """This machine's name, for its token: the short hostname, in the
    characters a token's name may hold. It names the machine; it proves
    nothing."""
    name = re.sub(r"[^A-Za-z0-9_.-]", "-", socket.gethostname().split(".")[0])
    return re.sub(r"^[^A-Za-z0-9]+", "", name)[:64] or "client"


def _own_version() -> str:
    """This client's version: VERSION beside it once installed, the PLUGIN
    file's in a checkout."""
    here = Path(__file__).resolve().parent
    try:
        return (here / "VERSION").read_text().strip()
    except OSError:
        pass
    try:
        m = re.search(r"^version: *(\S+)", (here / "PLUGIN").read_text(), re.M)
        return m[1] if m else ""
    except OSError:
        return ""


def _new_token(name: str) -> str:
    """POST /tokens with a user and password asked here, on the terminal, or
    read from stdin when it is not one. The password goes no further."""
    user = os.environ.get("XYMONAPI_USER", "")
    tty = sys.stdin.isatty()
    if not user:
        print("user: ", end="", file=sys.stderr, flush=True)
        user = sys.stdin.readline().strip()
        if not user:
            raise APIError("a user of the API is needed")
    if tty:
        pw = getpass.getpass(f"password for {user}: ")
    else:
        print(f"password for {user}: ", end="", file=sys.stderr, flush=True)
        pw = sys.stdin.readline().rstrip("\n")
        print(file=sys.stderr)
    auth = base64.b64encode(f"{user}:{pw}".encode()).decode()
    pw = ""
    req = urllib.request.Request(_url("/tokens"), method="POST",
                                 data=json.dumps({"client": name}).encode(),
                                 headers={"Content-Type": "application/json",
                                          "Authorization": f"Basic {auth}"})
    try:
        with open_url(req, 30) as r:
            token = json.loads(r.read(MAX_BODY)).get("token", "")
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise APIError(f"the API refused the password for {user}") from e
        raise APIError(f"xymonapi answered {e.code} for a token: {e.read().decode(errors='replace')}") from e
    except (urllib.error.URLError, OSError, ValueError) as e:
        raise APIError(f"no token from {URL}: {e}") from e
    if not token.startswith("xat_"):
        raise APIError(f"the API gave no token: {token!r}")
    return token


def connect(argv: list[str]) -> int:
    global URL, CA, TOKEN, TOKEN_FILE, _opener
    if not argv or argv[0] in ("-h", "--help") or len(argv) > 2:
        print("usage: xymonapi-connect URL [NAME]", file=sys.stderr)
        return 2
    url, name = argv[0].rstrip("/"), (argv[1] if len(argv) > 1 else "xymon")
    if not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", name):
        _say(f"a name is letters, digits, '.', '_' and '-': not {name!r}")
        return 2
    conf = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "xymon-api"
    token_file, ca_file = conf / f"{name}.token", conf / f"{name}-ca.pem"
    URL, TOKEN, _opener = url, "", None
    local = urlsplit(URL).scheme == "unix"
    # The server's certificate, or its CA, when this machine does not trust
    # it already: copied here first, by hand, over a channel already trusted.
    # Neither it nor a token kept from before has a part over the socket,
    # whose permissions are the credential: the settings printed then name
    # the socket alone.
    CA = "" if local else os.environ.get("XYMONAPI_CA") or (str(ca_file) if ca_file.is_file() else "")
    try:
        # Reached and trusted before anything is asked. A token kept from
        # before is used while it works.
        TOKEN_FILE = str(token_file) if token_file.is_file() and not local else ""
        try:
            health = api("/health")
        except APIError as e:
            if e.status != 401:
                if "does not trust" in str(e):
                    _say(f"{URL} has a certificate this machine does not trust: copy the server's "
                         f"certificate, or the CA that signed it, to {ca_file} and run this again")
                    return 1
                raise
            conf.mkdir(parents=True, exist_ok=True)
            TOKEN_FILE = ""
            token = _new_token(_machine())
            fd = os.open(token_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as f:
                f.write(token + "\n")
            os.chmod(token_file, 0o600)
            TOKEN_FILE = str(token_file)
            _say(f"a token for {_machine()} kept in {token_file} (mode 600); the API's /tokens lists and revokes it")
            health = api("/health")
    except APIError as e:
        _say(str(e))
        return 1
    except KeyboardInterrupt:
        print(file=sys.stderr)
        return 130
    if not TOKEN_FILE:
        _say(f"{URL} asks no credential: the socket's permissions, or the API's settings, let this "
             "user in; nothing is kept here" if urlsplit(URL).scheme == "unix" else
             f"{URL} asks no password, so no token is needed; nothing is kept here")
    old = conf / f"{name}.password"
    if old.exists():
        old.unlink()
        _say(f"removed {old}: the token replaces the password, which is no longer kept")
    # Whether the two sides run the same version: compatibility is what a
    # version says, so a difference is worth knowing, and who can act on it.
    theirs, mine = health.get("version", ""), _own_version()
    t, m = _triple(theirs), _triple(mine)
    if t and m and t < m:
        _say(f"the API runs xymonapi {theirs}, this machine's client {mine}: the server's admin "
             "can update it, with ./install.sh install from an updated checkout")
    elif t and m and t > m:
        _say(f"the API runs xymonapi {theirs}, this machine's client {mine}: update here, "
             "with git pull && ./install.sh install")
    settings = {"XYMONAPI_URL": URL}
    if TOKEN_FILE:
        settings["XYMONAPI_TOKEN_FILE"] = TOKEN_FILE
    if CA:
        settings["XYMONAPI_CA"] = CA
    for k, v in settings.items():
        print(f"{k}={shlex.quote(v)}")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] != ["connect"]:
        print("usage: xymonapi_client.py connect URL [NAME]", file=sys.stderr)
        sys.exit(2)
    sys.exit(connect(sys.argv[2:]))
