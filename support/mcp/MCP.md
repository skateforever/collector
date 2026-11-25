# collector-mcp — MCP server for collector's results

`collector-mcp.py` exposes collector's recon results (the same two
sources `app.py`/the dashboard read) as [MCP](https://modelcontextprotocol.io/)
tools, so an MCP-speaking client — Claude Desktop, Claude Code, any
other agent — can query targets, runs, subdomains, findings, and diffs
directly, without going through the HTTP dashboard.

It is **read-only**, same contract as the dashboard: the recon flow
(`db_usage()`) is the only writer. This server never calls collector,
never starts/stops a scan, and never writes to `collector-results` or
`outputs/`.

## Why a separate file (and a separate directory) from app.py

`app.py` is a Flask app meant to run as a long-lived gunicorn worker
**inside** the collector container (via `-ru|--report-up`), serving
HTML over HTTP. `collector-mcp.py` is meant to run as a **local
process on the host**, launched on demand by an MCP client over stdio
— a different process model, a different protocol, and (critically) a
different filesystem view. Bolting MCP support onto `app.py` would
mean one file serving two audiences with two different path
assumptions; keeping them separate keeps each one's assumptions
simple. The two still share the same read logic (SQLite schema,
artifact whitelist, nuclei parser) by design — see
[Keeping this in sync with app.py](#keeping-this-in-sync-with-apppy)
below.

It lives under `support/mcp/` rather than `app-report/` for the same
reason: `app-report/` is gunicorn's own working directory (`cd
app-report && gunicorn app:app`, see `functions/app_report.sh`) — this
script sitting next to `app.py` there was never a functional
dependency, gunicorn never looks at any other file in that directory.
`support/` is where the rest of collector's auxiliary, non-scan
tooling already lives (`support/docker/`, `support/runtime/`,
`support/templates/`), so `support/mcp/` keeps this script out of the
dashboard's own directory without changing how either one runs.

## The container/host path problem (read this before anything else)

collector only ever runs inside Docker, so every `report_dir` it
writes to `collector-results` is a **container-side path**
(`/opt/collector/outputs/<domain>/<run>/report`, from `output_dir` in
`conf.d/operation.conf`). `app.py` never needs to translate that path
because it runs **inside the same container**, where that prefix is
real.

`collector-mcp.py` is meant to run on the **host** instead. Without
translation, every `report_dir` read from the DB would point at a path
that simply doesn't exist outside the container, and every
file-reading tool (`get_artifact`, `get_raw_file`, `get_findings`,
`diff_runs`) would fail.

The server handles this with one rewrite, applied once inside
`safe_report_path()` before touching the filesystem: any `report_dir`
starting with the container-side prefix (read from `operation.conf`'s
own `output_dir` — see [Configuration](#configuration) below) has that
prefix replaced with the host-side `OUTPUT_DIR`. If `report_dir`
doesn't start with that prefix — e.g. you're running this server
*inside* the container too, where `COLLECTOR_OUTPUT_DIR` is already
the container path — it's left unchanged.

Since the container-side prefix is read straight out of
`conf.d/operation.conf`'s `output_dir`, **this rewrite stays correct
automatically** even if `output_dir` is changed from its default —
there's nothing to keep in sync by hand.

## Configuration

Every setting below follows the same precedence: **(1)** an
environment variable, if set; **(2)** the matching literal in
`conf.d/operation.conf`; **(3)** a hardcoded fallback.
`conf.d/operation.conf` is the intended source of truth for an
installed, unattended deployment — set values there once. Environment
variables remain for a one-off override (debugging, CI, a client
config that needs something different from the shared file) without
editing that file.

`conf.d/operation.conf` is read with a **deliberately dumb grep/sed
reader** (`_read_operation_conf_var()`, same approach
`collector-docker`'s own reader already uses for `app_report_*`) — not
a shell parser, so it doesn't resolve arbitrary `${...}`/`$(...)`
shell expressions. The one exception is the literal substring
`"${collector_path}"` specifically: it's substituted directly with
`REPO_ROOT` (this file's own, Python-computed equivalent of
`collector_path` — both resolve to the repo's root directory), since
`conf.d/operation.conf` already uses `${collector_path}` throughout for
its own repo-relative paths (`collector_db`,
`collector_js_api_extractor`, etc.) — `collector_mcp_output_dir`
follows that same convention rather than introducing a different one.
Any OTHER `${...}`/`$(...)` in a value this server reads is passed
through as a literal string, unresolved — don't introduce one.

| Variable | conf.d/operation.conf | Default | Meaning |
|----------|------------------------|---------|---------|
| `COLLECTOR_DB` | *(rebuilt from `app_report_dir` + `collector_db_name`, both literals)* | `${collector_path}/app-report/db/collector-results` | Path to the SQLite results DB, opened `mode=ro`. |
| `COLLECTOR_OUTPUT_DIR` | `collector_mcp_output_dir` | `${collector_path}/outputs` | Host-side path corresponding to the container's `outputs/` — i.e. the same directory `collector-docker`'s `OUTPUTS_DIR` bind-mounts from. Ships as `"${collector_path}/outputs"` — correct out of the box for any checkout; only change it if `OUTPUTS_DIR` points somewhere else. |
| `COLLECTOR_CONTAINER_OUTPUT_DIR` | `output_dir` *(reused directly)* | `/opt/collector/outputs` | The container-side prefix stored in `report_dir` — this is `operation.conf`'s own `output_dir`, the exact value collector itself writes to the DB. Only set the env var if `operation.conf` genuinely isn't reachable from wherever this server runs. |
| `COLLECTOR_MCP_TRANSPORT` | `collector_mcp_transport` | `stdio` | `stdio` (local subprocess) or `streamable-http` (plain HTTP server — see the dedicated section and its security warning below). Ships as `streamable-http` so `-mu|--mcp-up` works out of the box; set back to `stdio` if you only ever launch this script directly from an MCP client. |
| `COLLECTOR_MCP_CONTAINER_ADDRESS` | `collector_mcp_container_address` | `0.0.0.0` | The actual bind address `FastMCP(host=...)` uses, only relevant for `streamable-http`. Same split as `app.py`'s `APP_REPORT_CONTAINER_ADDRESS`: this is the CONTAINER-internal address — `functions/mcp_server.sh` (the `-mu|--mcp-up`/`-md|--mcp-down` lifecycle) reads `collector_mcp_container_address` from `conf.d/operation.conf` and exports it for you, ships at `0.0.0.0` so `-mu` works out of the box through `docker run -p`; `127.0.0.1` here is unreachable through `-p` no matter how correctly the port is published. |
| `COLLECTOR_MCP_HOST` | `collector_mcp_host` | `127.0.0.1` | The operator-facing address — what you type into your client, and what `collector-docker` publishes `-mu|--mcp-up` on (the `-p` flag's host-side half). Deliberately **not** the bind address above, same reason `app_report_host_address` isn't `app_report_container_address`. |
| `COLLECTOR_MCP_PORT` | `collector_mcp_port` | `8010` | Bind port, only used when the transport is `streamable-http`. **Must not collide with `app_report_container_port`/`app_report_host_port`** — see the next section. |

`COLLECTOR_DB`'s conf-file path is special: `operation.conf`'s own
`collector_db` variable is itself `${collector_path}/${app_report_dir}/db/${collector_db_name}`
— `${app_report_dir}` isn't handled by the `${collector_path}`
substitution above, so this one expression as a whole still can't be
read directly. `app_report_dir` and `collector_db_name` are plain
literals on their own though, so `COLLECTOR_DB`'s default is rebuilt
from those two directly instead of trying to read `collector_db`
itself.

The hardcoded fallbacks (used only when `conf.d/operation.conf` itself
can't be found or read at all) resolve relative to `${collector_path}`
(`collector-mcp.py`'s own location, two levels up —
`support/mcp/collector-mcp.py` → `${collector_path}`, computed in
Python as `REPO_ROOT`), same anchoring rationale as `app.py`'s own
one-level-up resolution.

If you're running this checkout exactly as documented in the main
[README](../../README.md) (`collector-docker` with its default
`OUTPUTS_DIR`/`APP_REPORT_DB_DIR`), the defaults above already point at
the right place — **no configuration is required**, just point your
MCP client at the script (see below).

### Port conflict with the app-report dashboard

`collector_mcp_port` (default `8010`) is deliberately **not**
`app_report_container_port`/`app_report_host_port` (`8000`/`8001` by
default) — the dashboard and this server are two independent
processes that can both be running at the same time (neither depends
on the other being up), so they need two different ports. If
`collector_mcp_port` (or `COLLECTOR_MCP_PORT`) is ever set to the same
value as either app-report port, **the server refuses to start** over
the HTTP transport with a clear error naming both conflicting values —
rather than silently failing to bind, or binding and quietly stealing
traffic from whichever process started second. This check only runs
for `streamable-http`; `stdio` never binds a port, so it's unaffected
no matter what `collector_mcp_port` is set to.

## Running it as a managed service via `collector --mcp-up`/`--mcp-down`

Everything above describes the *stdio* model: an MCP client (Claude
Desktop/Code) spawns `collector-mcp.py` itself, as its own subprocess,
for the lifetime of that client. That still works and needs nothing
below.

As an alternative — for a client on another machine, or just to keep
the server running independently of any one client's lifecycle —
`collector`'s own CLI can manage it as a long-lived `streamable-http`
service, the same way `-ru|--report-up`/`-rd|--report-down` already
manage the app-report dashboard:

```bash
# Native collector (inside the container, or run directly on a host checkout):
collector --mcp-up       # starts collector-mcp.py, keeps the process alive
collector --mcp-down     # stops it (SIGTERM, wait 5s, SIGKILL if needed)

# Or via collector-docker, same container/lifecycle as --report-up:
collector-docker --mcp-up
collector-docker --mcp-down
collector-docker -d example.com --recon --report-up --mcp-up   # both services, one container
```

This path requires `collector_mcp_transport="streamable-http"` in
`conf.d/operation.conf` — `--mcp-up` refuses to start otherwise, with a
message naming that exact fix, since `stdio` has no network port for a
background/foreground service to bind. `--mcp-up` alone keeps the
process in the foreground (Ctrl-C stops it); combined with a recon
target it starts in the background at the tail of the run, after
`--report-up`'s own dashboard if both are passed, and the container
stays alive afterward for as long as the server should keep serving —
same pattern as the dashboard's own `_collector_hold_for_dashboard`
(here, `_collector_hold_for_mcp_server`) in `collector`. `--report-up
--mcp-up` passed together with NO target flag is a special case of
that same "alone" dispatch: both services start in the BACKGROUND
(neither one `exec`s into PID 1) and `collector` just holds the
process open, specifically so `--mcp-down` can stop only the MCP
server's own pid afterward without taking the whole container (and the
dashboard) down with it — `exec`-replacing PID 1 with either service
individually would make a SIGTERM to that service equivalent to a
SIGTERM to the container's init.

The implementation is `functions/mcp_server.sh`, deliberately mirroring
`functions/app_report.sh`'s shared-pidfile, dual background/foreground
design — see that file's own header comment for the full rationale
(stale-pidfile detection across container restarts, PID-namespace
caveats, etc.), which applies here unchanged. `collector-docker
--mcp-down` is narrower than `--report-down`: it `docker exec`s
`collector --mcp-down` into the running container (stopping only this
server's own pid) instead of stopping the whole container, so an
app-report dashboard also running there is left untouched.

## Client setup

### Claude Desktop / Claude Code

Add an entry to your MCP client's config (`claude_desktop_config.json`
for Claude Desktop; `.mcp.json` or `claude mcp add` for Claude Code):

```json
{
  "mcpServers": {
    "collector": {
      "command": "python3",
      "args": ["/absolute/path/to/collector/support/mcp/collector-mcp.py"]
    }
  }
}
```

Use an **absolute path** — the client launches this as its own
process, with its own working directory, so a relative path isn't
reliable. No `env` block is needed for the common case: every setting
(DB path, output dir, transport) is already read from
`conf.d/operation.conf` (see [Configuration](#configuration) above).
Add one only to override something for this specific client without
touching the shared conf file, e.g.:

```json
{
  "mcpServers": {
    "collector": {
      "command": "python3",
      "args": ["/absolute/path/to/collector/support/mcp/collector-mcp.py"],
      "env": {
        "COLLECTOR_OUTPUT_DIR": "/custom/outputs/path"
      }
    }
  }
}
```

### Any other MCP client

`collector-mcp.py` speaks stdio transport by default — the client
spawns it as a subprocess and talks newline-delimited JSON-RPC over
its stdin/stdout. Any client that supports stdio MCP servers works the
same way; consult that client's own docs for where its server config
file lives.

If the server is running over `streamable-http` instead (e.g. via
`-mu|--mcp-up`, see below), the client config shape is different —
`type`/`url`, not `command`/`args` — see
[Remote access over HTTP](#remote-access-over-http)'s "Option B —
HTTP" section below for the exact JSON and a verified `claude mcp add`
one-liner.

## Remote access over HTTP

stdio only works when the client can spawn the server as its own
*local* subprocess. If the client is on a **different machine** than
the one running collector, stdio can't reach it — you need either an
SSH tunnel (keeps stdio, no code change, see below) or this server's
built-in HTTP transport.

### ⚠️ Security warning — read before enabling this

Setting `COLLECTOR_MCP_TRANSPORT=streamable-http` turns this script
into an HTTP server that answers MCP tool calls — including
`get_artifact`/`get_findings`, which return subdomains, emails, and
extracted JS secrets. **This server ships with no authentication over
HTTP.** Anyone who can reach `COLLECTOR_MCP_CONTAINER_ADDRESS:COLLECTOR_MCP_PORT`
can call every tool with no login, no token, nothing. This is
deliberately minimal — the SDK's `FastMCP` supports OAuth
(`auth=`/`token_verifier=` in its constructor), but wiring that up is
out of scope here; this is meant for an early-stage, trusted,
same-network setup, not a production or internet-facing one.

Concretely:

- **Don't** set `COLLECTOR_MCP_CONTAINER_ADDRESS=0.0.0.0` (or any
  routable address) on a machine reachable from the public internet.
- **Do** keep it on a private/VPN network you trust, and firewall the
  port to only the specific client machine(s) that need it.
- If you need this reachable from somewhere less trusted, prefer the
  SSH tunnel approach below instead — it reuses your existing SSH auth
  and never opens a new network port at all.

### Option A — SSH (no code change, works today)

Keep `COLLECTOR_MCP_TRANSPORT` unset (stdio) and have the *client*
launch the server over SSH instead of locally:

```json
{
  "mcpServers": {
    "collector": {
      "command": "ssh",
      "args": ["user@remote-host", "python3", "/path/to/collector/support/mcp/collector-mcp.py"]
    }
  }
}
```

SSH tunnels stdio transparently, so the script still runs exactly as
tested in this document — on `remote-host` itself, where
`COLLECTOR_DB`/`COLLECTOR_OUTPUT_DIR` resolve correctly with no path
rewriting beyond what's already documented above. Requires: `mcp`
installed in the Python environment `ssh ... python3` resolves to on
the remote host, and working key-based SSH auth.

### Option B — HTTP (same network, see the warning above)

Either set it permanently in `conf.d/operation.conf`:

```bash
# conf.d/operation.conf
collector_mcp_transport="streamable-http"
collector_mcp_container_address="0.0.0.0"   # the actual bind address
collector_mcp_host="<that machine's LAN/public IP>"   # what you'll type into the client
collector_mcp_port="8010"   # keep this different from app_report_container_port/app_report_host_port
```

or override it for one invocation via the environment, without
touching the conf file:

```bash
cd support/mcp
COLLECTOR_MCP_TRANSPORT=streamable-http \
COLLECTOR_MCP_CONTAINER_ADDRESS=0.0.0.0 \
COLLECTOR_MCP_PORT=8010 \
python3 collector-mcp.py
```

The server listens on `/mcp` (streamable-http, the current MCP spec's
HTTP transport) at `http://<that-machine's-IP>:8010/mcp`. Point the
remote MCP client at that URL. Unlike stdio's `command`/`args` shape
(see [Client setup](#client-setup) above), an HTTP server is
configured with a `type`/`url` pair instead — no process for the
client to spawn, it just connects:

```json
{
  "mcpServers": {
    "collector": {
      "type": "http",
      "url": "http://<that-machine's-IP>:8010/mcp"
    }
  }
}
```

For Claude Code specifically, the equivalent one-liner (verified
against the CLI — this is the exact shape it writes):

```bash
claude mcp add --transport http collector http://<that-machine's-IP>:8010/mcp
```

Other clients accept the same `type: "http"` / `url` shape in their
own config file, but confirm against that client's own docs — this is
what Claude Code does, not a universal guarantee.

One SDK detail worth knowing: `FastMCP` auto-enables DNS-rebinding
protection (which would reject any request whose `Host` header isn't
`127.0.0.1`/`localhost`) **only when bound to `127.0.0.1`**. Binding to
`0.0.0.0` (or any other address) disables that protection automatically
— confirmed against the installed SDK version — so no extra
`transport_security` configuration is needed to accept external
requests once you've set `COLLECTOR_MCP_CONTAINER_ADDRESS`.

### Running it by hand (debugging)

```bash
cd support/mcp
pip install -r requirements.txt   # installs mcp
python3 collector-mcp.py
```

It'll sit there reading stdin for JSON-RPC — that's expected, it's
meant to be driven by a client, not run interactively. Ctrl-C to exit.

To sanity-check it's reading the right DB/outputs, call the `health`
tool through your MCP client once connected — it reports the resolved
`db`/`output_dir` paths and whether the DB actually opened. That's the
most reliable check: the script's filename has a hyphen, so it can't
be `import`ed as a plain module for a quick one-off check outside the
MCP protocol itself.

## Testing with curl

The two sections above cover running the server; this one covers
proving it actually answers, with nothing but `curl` — no MCP client,
no Claude Desktop/Code config, useful when you've just set
`collector_mcp_transport=streamable-http` on a box and want to confirm
it's reachable before pointing a real client at it.

This only applies to the `streamable-http` transport. `stdio` has no
HTTP endpoint at all — there's nothing for `curl` to hit; the MCP
client talks to it over the subprocess's stdin/stdout instead.

Everything below was run against this server (SDK version
`mcp==1.x`, server reporting itself as `collector-mcp` 1.30.0 in
`initialize`'s response) with:

```bash
cd support/mcp
MCP_PORT=8011   # anything free and != app_report_container_port/app_report_host_port
COLLECTOR_MCP_TRANSPORT=streamable-http COLLECTOR_MCP_CONTAINER_ADDRESS=127.0.0.1 COLLECTOR_MCP_PORT=$MCP_PORT \
python3 collector-mcp.py &
```

(`127.0.0.1` is correct here specifically because `curl` below runs on
this SAME machine, no Docker `-p` in between — `COLLECTOR_MCP_CONTAINER_ADDRESS`
is the actual bind address; see [Configuration](#configuration) above
for why that's a different variable from the operator-facing
`COLLECTOR_MCP_HOST`/`collector_mcp_host`.)

### The protocol shape you'll actually see

streamable-http is **stateful** and the SDK's `Accept` handling is
stricter than it looks at first glance:

- Sending `Accept: application/json` alone gets a `406 Not
  Acceptable` — the SDK requires the client to accept **both**
  `application/json` and `text/event-stream` on every request,
  even though the response below always comes back as
  `text/event-stream` in practice (one `event: message` / `data: ...`
  frame per JSON-RPC response — a single-shot SSE stream, not a
  file download). So every request needs:

  ```
  -H "Accept: application/json, text/event-stream"
  ```

- The **first** `initialize` response carries a `mcp-session-id`
  response header. Every request after that — including the
  `notifications/initialized` notification — must send that same
  value back as an `mcp-session-id` *request* header, or the server
  answers `400 Bad Request: Missing session ID`. There's no cookie
  jar involved; it's a single header you capture once and replay.

### Step by step

```bash
MCP_PORT=8011   # match whatever you started the server with above

# 1. initialize — capture both the response body and the mcp-session-id
#    header the server hands back for this session.
INIT=$(curl -s -i -X POST "http://127.0.0.1:${MCP_PORT}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}')
echo "$INIT"
SESSION_ID=$(echo "$INIT" | grep -i '^mcp-session-id:' | awk '{print $2}' | tr -d '\r')
echo "SESSION_ID=$SESSION_ID"
```

The response is a `200 OK` with `content-type: text/event-stream` and
an `mcp-session-id` header; the body's `data:` line is the JSON-RPC
result — a `serverInfo.name` of `"collector-mcp"` confirms you're
talking to the right process.

```bash
# 2. notifications/initialized — required by the MCP handshake before
#    any other call; the server replies 202 Accepted with an empty
#    body (it's a notification, not a request — there's no "id" and
#    nothing to return).
curl -s -i -X POST "http://127.0.0.1:${MCP_PORT}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
```

```bash
# 3. tools/list — confirm the full tool set is exposed. Pipe through
#    `python3 -m json.tool` or `jq` if you want it readable; the raw
#    SSE "data:" line is valid JSON-RPC on its own.
curl -s -X POST "http://127.0.0.1:${MCP_PORT}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
```

The result's `tools` array should list all 11: `list_targets`,
`get_target`, `list_runs`, `get_run`, `list_artifact_kinds`,
`get_artifact`, `list_raw_file_kinds`, `get_raw_file`, `get_findings`,
`diff_runs`, `health` — each with its `inputSchema`. If this comes
back empty or 400s, the session ID didn't make it onto the request.

```bash
# 4. tools/call health — the one tool that needs no target/run data to
#    exist; it just confirms the SQLite DB opens.
curl -s -X POST "http://127.0.0.1:${MCP_PORT}/mcp" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: ${SESSION_ID}" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"health","arguments":{}}}'
```

The JSON-RPC `result` looks like:

```json
{"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"{\n  \"ok\": true,\n  \"targets\": 3,\n  \"db\": \"/path/to/collector/app-report/db/collector-results\",\n  \"output_dir\": \"/path/to/collector/outputs\"\n}"}],"isError":false}}
```

Two layers to read here, and this is the part that trips people up:
`result.isError` is the **MCP-level** success flag (`false` means the
tool ran without raising), and `result.content[0].text` is a **string**
containing the tool's own JSON output — it isn't already a nested JSON
object, because MCP tool results are text/content blocks, not
arbitrary structured values. Pull that string out and parse it again
(`... | jq -r '.result.content[0].text' | jq .` once you've stripped
the `event:`/`data:` SSE framing) to get at `ok`/`targets`/`db`/
`output_dir`.

### Reading common failures

- **`curl: (7) Failed to connect to 127.0.0.1 port 8011 after 0 ms:
  Couldn't connect to server`** — nothing is listening on that
  host:port. Either the server isn't running, it's still on `stdio`
  (check `collector_mcp_transport`/`COLLECTOR_MCP_TRANSPORT`), or you
  used the wrong port.
- **The process exits immediately on startup**, printing something
  like `collector-mcp: port 8000 collides with the app-report
  dashboard (app_report_container_port=8000,
  app_report_host_port=8001 in conf.d/operation.conf)...` — you picked
  a `collector_mcp_port`/`COLLECTOR_MCP_PORT` that matches the
  dashboard's port. This is `sys.exit()`, not a crash; there's no HTTP
  response to curl at all, because the port is never bound. Pick a
  different port.
- **Calling a tool that doesn't exist** does *not* produce an HTTP
  error — the HTTP exchange itself is a normal `200 OK`. The error
  shows up one layer in, inside the JSON-RPC result:
  `{"jsonrpc":"2.0","id":4,"result":{"content":[{"type":"text","text":"Unknown tool: does_not_exist"}],"isError":true}}`.
  Any malformed `tools/call` (bad tool name, or a real tool raising —
  see [Error handling](#error-handling) below) looks like this:
  `isError: true` with a human-readable message in `content[0].text`,
  never a 4xx/5xx.
- **Omitting or dropping the `mcp-session-id` header** on any request
  after `initialize` gets `400 Bad Request: Missing session ID` — the
  session isn't implicit or cookie-based, it's whatever you captured
  from `initialize`'s response header.

## Tool reference

Every tool is read-only. Tools that take an optional `run_id` default
to **the domain's most recent run** when it's omitted — you rarely
need to call `list_runs`/`get_target` first just to find the latest
`run_id`.

| Tool | Purpose |
|------|---------|
| `health()` | Confirms the DB opens; reports the resolved `DB_PATH`/`OUTPUT_DIR`. Call this first if anything else errors. |
| `list_targets()` | Every ingested domain with its latest run's headline numbers. Start here. |
| `get_target(domain)` | One target's profile (`targets` row) plus its full run history. |
| `list_runs(domain?, mode?, page?, per_page?)` | Paginated run listing across all targets, optionally filtered by domain substring and/or mode (`recon`, `webapp-enum`, `url`, ...). |
| `get_run(domain, run_id?)` | One run's full `recon_runs` row — counts, timestamps, status, `report_dir`. |
| `list_artifact_kinds()` | The valid `kind` values for `get_artifact()`, with their labels and backing filenames. |
| `get_artifact(domain, kind, run_id?, q?, page?, per_page?)` | Paginated, filterable lines of one artifact file (subdomains, URLs, IPs, emails, JS secrets, ...). |
| `list_raw_file_kinds()` | The valid `kind` values for `get_raw_file()`. |
| `get_raw_file(domain, kind, run_id?, max_lines?)` | A whitelisted file verbatim (nmap/Shodan output, the LLM prompt, precomputed diffs), clipped to `max_lines`. |
| `get_findings(domain, run_id?, severity?, q?, page?, per_page?)` | Nuclei findings, severity-filterable, with per-severity counts. |
| `diff_runs(domain, run_from, run_to)` | What's new/gone between two runs across subdomains, IPs, URLs, vhosts, emails. |

### `get_artifact` kinds

Same whitelist as the dashboard's artifact pages — call
`list_artifact_kinds()` for the authoritative, live list; as of this
writing:

`subdomains_alive`, `subdomains_found`, `subdomains_aliases`,
`subdomains_thirdpart`, `subdomains_without_resolution`,
`subdomains_excluded`, `subdomains_infrastructure`,
`subdomains_internal_ipv4`, `subdomains_external_ipv4`,
`subdomains_external_ipv6`, `zone_transfer`, `ips`, `infra_as`,
`infra_blocks`, `webapp_consolidated`, `robots_urls`, `vhosts_strong`,
`emails`, `js_secrets`, `js_params`.

### `get_raw_file` kinds

Call `list_raw_file_kinds()` for the live list; as of this writing:

`nmap`, `shodan`, `llm_prompt`, `domains_diff`, `infra_ipv4_diff`,
`webapp_consolidated_diff`, `vhost_diff`, `email_diff`, `nuclei_diff`.

## Error handling

Tools raise a Python exception (`LookupError` for an unknown
domain/run, `ValueError` for an unknown `kind`, `FileNotFoundError`/
`PermissionError` for a missing or out-of-bounds `report_dir`) instead
of returning an error object. The MCP SDK turns that into a tool
result with `isError: true` and the exception's message — the client
sees a clear, specific error ("no run 'recon_20991301' found for
domain 'example.com'") rather than a generic failure or a silently
empty result.

## Security notes

See [Remote access over HTTP](#remote-access-over-http) above for the
HTTP-transport-specific warning (no authentication). The notes below
apply regardless of transport.

- **Read-only SQLite**: the DB connection is opened as
  `file:<path>?mode=ro` — SQLite itself refuses any write through that
  handle, independent of file permissions.
- **Path traversal**: `safe_report_path()` (a direct port of `app.py`'s
  own guard) refuses to resolve outside `OUTPUT_DIR`, rejects any path
  segment containing `..` or a leading `/`, and re-checks the final
  resolved path a second time after joining — the same defense
  `app.py` uses for its drill-down routes.
- **Whitelisted files only**: `get_artifact`/`get_raw_file` only ever
  open filenames listed in `ARTIFACT_KINDS`/`RAW_FILES` — this is not a
  generic file browser, and adding a new exposable file is a deliberate
  code change, not something a caller can request ad hoc.
- **No write path at all**: there is no tool, in this file, that calls
  anything other than `sqlite3.connect(..., uri=True)` in read-only
  mode and `Path.open("r", ...)`. If you need to extend this server,
  keep it that way — any write capability changes the trust model
  completely (an MCP client effectively gets to run that write on your
  behalf).

## Keeping this in sync with app.py

`collector-mcp.py` intentionally duplicates (rather than imports) a
few things from `app.py`: `ARTIFACT_KINDS`, `RAW_FILES`,
`safe_report_path()`, the nuclei line parser, and the pagination/
substring-filter helpers. This is deliberate, not an oversight — this
server has to work **standalone**, with no Flask app/request context,
and must not accidentally instantiate a Flask app instance just to
borrow one function from it.

The cost of that duplication: if you add a new artifact kind, a new
raw-file kind, or change the nuclei output format `app.py` parses,
mirror the change here too. Nothing enforces this automatically — it's
a manual step, flagged here so it isn't missed.

## Requirements

`support/mcp/requirements.txt` has the one dependency this file needs
— `mcp<2` — kept separate from `app-report/requirements.txt`
(flask/gunicorn, for `app.py`): the two run as entirely different
processes and don't need each other's dependencies installed. Pinned
below 2.x because `FastMCP` was renamed/restructured in the SDK's 2.x
line; 1.x is what current MCP clients (Claude Desktop, Claude Code)
target, and is what every example in this document was verified
against.
