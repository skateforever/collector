"""
collector-mcp — MCP server exposing collector's results as tools for an
LLM/agent client (Claude Desktop, Claude Code, any MCP-speaking client).

Read-only by design, same contract as app.py: the recon flow (db_usage)
is the only writer. This server reads the exact same two sources app.py
does, directly — not over HTTP — so it has no dependency on the Flask
dashboard being up:

  1. collector-results (SQLite, opened with mode=ro) — targets, runs,
     counts, trends.
  2. report_dir/*.txt files written by the recon flow — the actual
     subdomains/URLs/findings/etc content. The DB stores report_dir
     paths but not file contents; this server opens them lazily, with
     the same path-traversal guard as app.py (rooted at
     COLLECTOR_OUTPUT_DIR).

Configuration precedence, for every setting below: (1) an environment
variable, if set; (2) the matching value in conf.d/operation.conf,
read by _read_operation_conf_var() — a deliberately dumb grep/sed
reader (same approach collector-docker's own
_read_operation_conf_var() uses for web_report_*), not a shell parser,
so operation.conf's own ${...}-expansions aren't resolved in general —
the one exception is "${collector_path}" specifically, substituted
directly with REPO_ROOT (see _read_operation_conf_var() below) since
that's the one expansion operation.conf uses throughout for its own
repo-relative paths; (3) a hardcoded fallback. conf.d/operation.conf is
the single source of truth for an installed, unattended deployment;
environment variables remain for a one-off override without editing
that file (e.g. a quick debugging session).

This file lives under support/mcp/ (two levels below the repo root,
not sibling to support/web-report/db/ or outputs/) — see REPO_ROOT
below for how its path fallbacks account for that.

COLLECTOR_CONTAINER_OUTPUT_DIR / collector_mcp_output_dir exist only
because this server (unlike app.py) is meant to run on the HOST while
report_dir in the DB is always a container-side path — see
to_host_path() below and support/mcp/MCP.md.

Transport: stdio by default (what Claude Desktop/Code launch as a
local subprocess — no network port, no auth to configure). Set
collector_mcp_transport=streamable-http in conf.d/operation.conf (or
COLLECTOR_MCP_TRANSPORT=streamable-http in the environment) to serve
plain HTTP instead, for a client on another machine. That HTTP mode
ships with NO AUTHENTICATION — see the security warning in
support/mcp/MCP.md before enabling it on anything beyond a trusted,
same-network test setup. See support/mcp/MCP.md for the client config
snippet and the full tool reference either way.
"""

from __future__ import annotations

import os
import re
import sqlite3
import sys
from pathlib import Path
from typing import Optional

from mcp.server.fastmcp import FastMCP

# This file sits at ${collector_path}/support/mcp/collector-mcp.py —
# two levels below ${collector_path}, same depth as app.py's own
# (${collector_path}/support/web-report/). REPO_ROOT is this file's own,
# Python-computed equivalent of collector_path (see
# _read_operation_conf_var() below for why that equivalence matters).
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OPERATION_CONF = REPO_ROOT / "conf.d" / "operation.conf"


def _read_operation_conf_var(name: str) -> str:
    """Read a single conf.d/operation.conf variable (plain NAME="value"
    or NAME=value lines only). Same dumb grep/sed approach as
    collector-docker's own _read_operation_conf_var() — not a shell
    parser, so arbitrary ${...} expansions aren't resolved. The one
    exception is literally "${collector_path}" (used throughout
    operation.conf, e.g. collector_db/collector_js_api_extractor) —
    collector_path is always this repo's own root directory (collector
    itself sets it via `collector_path=$(dirname "$0")"`), which is
    exactly what REPO_ROOT already is here, so that one substring is
    replaced directly. Returns "" if the file or the variable is
    missing."""
    if not OPERATION_CONF.is_file():
        return ""
    pattern = re.compile(rf'^{re.escape(name)}=\"?([^\"\n]*)\"?\s*$')
    value = ""
    with OPERATION_CONF.open("r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = pattern.match(line.rstrip("\n"))
            if m:
                value = m.group(1)  # last match wins, same as grep | tail -1
    return value.replace("${collector_path}", str(REPO_ROOT))


def _config(env_name: str, conf_name: str, default: str) -> str:
    """Precedence: environment variable > conf.d/operation.conf > default."""
    return os.environ.get(env_name) or _read_operation_conf_var(conf_name) or default


# Same anchoring rationale as app.py: these fallbacks only matter when
# the server is run without operation.conf readable and without the
# env vars collector-docker/start_web_report normally export, and
# should still point at the real locations rather than wherever the
# caller happened to `cd` from.
#
# collector_db in operation.conf is itself "${collector_path}/${web_report_dir}/db/${collector_db_name}"
# — an expression _read_operation_conf_var() can't resolve (no
# ${collector_path} in this Python process). web_report_dir and
# collector_db_name are plain literals though, so COLLECTOR_DB is
# rebuilt from those two instead of trying to read collector_db
# itself. COLLECTOR_OUTPUT_DIR has no such equivalent in
# operation.conf (output_dir there is always the CONTAINER path, see
# CONTAINER_OUTPUT_DIR below) — collector_mcp_output_dir is this file's
# own, HOST-side counterpart.
_web_report_dir = _config("", "web_report_dir", "support/web-report")
_collector_db_name = _config("", "collector_db_name", "collector-results")
DB_PATH = Path(os.environ.get("COLLECTOR_DB") or (REPO_ROOT / _web_report_dir / "db" / _collector_db_name)).resolve()
OUTPUT_DIR = Path(_config("COLLECTOR_OUTPUT_DIR", "collector_mcp_output_dir", "") or (REPO_ROOT / "outputs")).resolve()

# report_dir, as stored in recon_runs, is ALWAYS the CONTAINER-side path
# (conf.d/operation.conf's own output_dir, "/opt/collector/outputs/..." —
# collector only ever runs inside Docker, so that's the only path it
# ever writes to the DB). app.py never needed to translate it because
# it runs INSIDE that same container, where that prefix is real. This
# server is meant to run on the HOST instead (stdio, launched by Claude
# Desktop/Code as a local process) — so every report_dir read from the
# DB has to be rewritten from the container prefix to OUTPUT_DIR before
# touching the filesystem. Reuses operation.conf's own output_dir
# directly (that's the exact prefix collector itself writes to the DB)
# rather than a second, easy-to-drift variable; COLLECTOR_CONTAINER_OUTPUT_DIR
# only needs to be set if operation.conf truly isn't reachable from here.
CONTAINER_OUTPUT_DIR = _config("COLLECTOR_CONTAINER_OUTPUT_DIR", "output_dir", "/opt/collector/outputs")


def to_host_path(container_report_dir: str) -> str:
    """Rewrite a report_dir read from the DB (container-side prefix)
    into the equivalent host-side path under OUTPUT_DIR. Falls through
    unchanged if it doesn't start with the expected container prefix —
    e.g. when this server runs INSIDE the container too (COLLECTOR_DB/
    COLLECTOR_OUTPUT_DIR set the same way app.py's are), so report_dir
    is already a real, directly-usable path."""
    if container_report_dir.startswith(CONTAINER_OUTPUT_DIR):
        return str(OUTPUT_DIR) + container_report_dir[len(CONTAINER_OUTPUT_DIR):]
    return container_report_dir


# Transport is stdio by default (what Claude Desktop/Code launch as a
# local subprocess) — set collector_mcp_transport=streamable-http in
# conf.d/operation.conf to instead serve plain HTTP, e.g. for a client
# on another machine on the same network. host/port only matter for
# the HTTP transport; stdio ignores them. See the big security warning
# in support/mcp/MCP.md before setting collector_mcp_host to anything
# other than 127.0.0.1 — this server ships NO AUTHENTICATION over
# HTTP, by design, for now (early-stage, same-network testing only).
TRANSPORT = _config("COLLECTOR_MCP_TRANSPORT", "collector_mcp_transport", "stdio")
# Same split as app.py's WEB_REPORT_CONTAINER_ADDRESS vs.
# web_report_host_address: BIND_HOST is what uvicorn actually binds to
# INSIDE this process's own network namespace (0.0.0.0 when launched
# via -mu|--mcp-up in a container — see conf.d/operation.conf's own
# comment on collector_mcp_container_address for why 127.0.0.1 there
# is unreachable through `docker run -p`). collector_mcp_host is a
# DIFFERENT setting — the operator-facing address collector-docker
# publishes on and prints in "is up" messages — and is deliberately
# NOT read here; binding to it directly was the bug that made -mu
# unreachable from outside the container when collector_mcp_host was
# left at its own default of 127.0.0.1.
BIND_HOST = _config("COLLECTOR_MCP_CONTAINER_ADDRESS", "collector_mcp_container_address", "127.0.0.1")
HTTP_PORT = int(_config("COLLECTOR_MCP_PORT", "collector_mcp_port", "8010"))

# Refuse to start over HTTP on the same port as the web-report
# dashboard — they're two unrelated services that can both be running
# at once (collector-mcp.py doesn't need the dashboard up, and vice
# versa — see this file's own module docstring), so a silent collision
# would mean one of them never actually binds, or MCP traffic hitting
# gunicorn (or vice versa) depending on start order. Only checked for
# the HTTP transport: stdio never binds a port at all.
if TRANSPORT != "stdio":
    _web_report_container_port = _config("", "web_report_container_port", "8000")
    _web_report_host_port = _config("", "web_report_host_port", "8001")
    _conflicting = {_web_report_container_port, _web_report_host_port} & {str(HTTP_PORT)}
    if _conflicting:
        sys.exit(
            f"collector-mcp: port {HTTP_PORT} collides with the web-report dashboard "
            f"(web_report_container_port={_web_report_container_port}, "
            f"web_report_host_port={_web_report_host_port} in conf.d/operation.conf). "
            "Set a different collector_mcp_port there, or COLLECTOR_MCP_PORT in the "
            "environment, before using the HTTP transport."
        )

mcp = FastMCP("collector-mcp", host=BIND_HOST, port=HTTP_PORT)


# ---------------------------------------------------------------------------
# DB plumbing — one short-lived connection per call, same mode=ro contract
# as app.py. No per-request caching here: MCP tool calls are infrequent
# and independent (no Flask request context to hang a cache off of), so
# simplicity wins over the handful of milliseconds a cache would save.
# ---------------------------------------------------------------------------


def get_db() -> sqlite3.Connection:
    if not DB_PATH.exists():
        raise FileNotFoundError(f"collector DB not found at {DB_PATH}")
    conn = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    return conn


def query(sql: str, params: tuple = ()) -> list[sqlite3.Row]:
    conn = get_db()
    try:
        return conn.execute(sql, params).fetchall()
    finally:
        conn.close()


def query_one(sql: str, params: tuple = ()) -> Optional[sqlite3.Row]:
    conn = get_db()
    try:
        return conn.execute(sql, params).fetchone()
    finally:
        conn.close()


def row_to_dict(row: sqlite3.Row) -> dict:
    return dict(row)


# ---------------------------------------------------------------------------
# Filesystem access — identical guard to app.py's safe_report_path, kept
# as its own copy rather than importing app.py: this server must work
# standalone (no Flask app context) and must not accidentally start a
# Flask app instance just to borrow one function.
# ---------------------------------------------------------------------------


def safe_report_path(report_dir: Optional[str], *parts: str) -> Path:
    if not report_dir:
        raise FileNotFoundError("run has no report_dir recorded")
    # Rewritten here, once, for every caller — report_dir as stored in the
    # DB is the container-side path (see to_host_path()'s own comment).
    base = Path(to_host_path(report_dir)).resolve()
    try:
        base.relative_to(OUTPUT_DIR)
    except ValueError:
        raise PermissionError(f"report_dir {base} is outside OUTPUT_DIR {OUTPUT_DIR}")
    for part in parts:
        if not part or part.startswith("/") or ".." in Path(part).parts:
            raise PermissionError(f"invalid path segment: {part!r}")
    final = base.joinpath(*parts).resolve()
    try:
        final.relative_to(OUTPUT_DIR)
    except ValueError:
        raise PermissionError(f"resolved path {final} is outside OUTPUT_DIR {OUTPUT_DIR}")
    return final


def read_lines(path: Path, *, skip_comments: bool = False) -> list[str]:
    if not path.is_file():
        return []
    out: list[str] = []
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if not line:
                continue
            if skip_comments and line.lstrip().startswith("#"):
                continue
            out.append(line)
    return out


# Same whitelist as app.py's ARTIFACT_KINDS — kept as its own copy for the
# same standalone-process reason as safe_report_path above. If a new
# artifact kind is added to app.py, mirror it here too (see MCP.md).
ARTIFACT_KINDS: dict[str, dict] = {
    "subdomains_alive":              {"file": "domains_alive.txt",            "label": "Subdomains alive"},
    "subdomains_found":              {"file": "domains_found.txt",            "label": "All subdomains discovered"},
    "subdomains_aliases":            {"file": "domains_aliases.txt",          "label": "Subdomain aliases (CNAME)"},
    "subdomains_thirdpart":          {"file": "domains_thirdpart.txt",        "label": "Third-party delegations"},
    "subdomains_without_resolution": {"file": "domains_without_resolution.txt", "label": "Subdomains w/o resolution"},
    "subdomains_excluded":           {"file": "domains_excluded.txt",         "label": "Excluded subdomains"},
    "subdomains_infrastructure":     {"file": "domains_infrastructure.txt",   "label": "Infrastructure (A/AAAA/MX/NS)"},
    "subdomains_internal_ipv4":      {"file": "domains_internal_ipv4.txt",    "label": "Internal IPv4 (RFC1918)"},
    "subdomains_external_ipv4":      {"file": "domains_external_ipv4.txt",    "label": "External IPv4"},
    "subdomains_external_ipv6":      {"file": "domains_external_ipv6.txt",    "label": "External IPv6"},
    "zone_transfer":                 {"file": "zone_transfer.txt",            "label": "Zone transfer (AXFR)"},
    "ips":                           {"file": "infra_ipv4.txt",               "label": "IPs"},
    "infra_as":                      {"file": "infra_as.txt",                 "label": "AS / BGP info"},
    "infra_blocks":                  {"file": "infra_blocks.txt",             "label": "Netblocks"},
    "webapp_consolidated":           {"file": "webapp_consolidated.txt",      "label": "Consolidated URLs"},
    "robots_urls":                   {"file": "robots_urls.txt",              "label": "robots.txt URLs"},
    "vhosts_strong":                 {"file": "etc_hosts_file.txt",           "label": "vhosts (/etc/hosts)"},
    "emails":                        {"file": "email_recon.txt",              "label": "Emails"},
    "js_secrets":                    {"file": "webapp_js_secrets.txt",        "label": "JS secrets", "skip_comments": True},
    "js_params":                     {"file": "webapp_js_params.txt",         "label": "JS params (DOM sinks)", "skip_comments": True},
}

# Same whitelist as app.py's RAW_FILES.
RAW_FILES: dict[str, dict] = {
    "nmap":                     {"path": ("scan", "nmap", "nmap_scan.txt"),     "label": "nmap scan"},
    "shodan":                   {"path": ("scan", "shodan", "shodan_scan.txt"), "label": "Shodan scan"},
    "llm_prompt":               {"path": ("llm-prompt.txt",),                   "label": "LLM prompt"},
    "domains_diff":             {"path": ("domains_diff.txt",),                 "label": "Subdomains diff"},
    "infra_ipv4_diff":          {"path": ("infra_ipv4_diff.txt",),              "label": "Infra IPv4 diff"},
    "webapp_consolidated_diff": {"path": ("webapp_consolidated_diff.txt",),     "label": "Consolidated URLs diff"},
    "vhost_diff":               {"path": ("vhost_subdomains_diff.txt",),        "label": "vhosts diff"},
    "email_diff":               {"path": ("email_recon_diff.txt",),            "label": "Emails diff"},
    "nuclei_diff":              {"path": ("scan", "nuclei", "nuclei_scan_diff.txt"), "label": "Nuclei diff"},
}

_NUCLEI_RE = re.compile(
    r"^\[(?P<template>[^\]]+)\]\s+\[(?P<proto>[^\]]+)\]\s+\[(?P<severity>[^\]]+)\]\s+(?P<rest>.+)$"
)


def parse_nuclei(path: Path) -> list[dict]:
    out: list[dict] = []
    if not path.is_file():
        return out
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.rstrip("\n").rstrip("\r")
            if not line:
                continue
            m = _NUCLEI_RE.match(line)
            if not m:
                out.append({"template": "—", "proto": "—", "severity": "unknown", "url": line, "extras": "", "raw": line})
                continue
            rest = m.group("rest").strip()
            url, _, extras = rest.partition(" ")
            out.append({
                "template": m.group("template"),
                "proto": m.group("proto"),
                "severity": m.group("severity").lower(),
                "url": url,
                "extras": extras.strip(),
                "raw": line,
            })
    return out


def paginate(items: list, page: int, per_page: int) -> tuple[list, int, int]:
    total = len(items)
    pages = max((total + per_page - 1) // per_page, 1) if total else 1
    page = max(min(page, pages), 1)
    start = (page - 1) * per_page
    return items[start:start + per_page], total, pages


def filter_substring(items: list[str], q: str) -> list[str]:
    if not q:
        return items
    needle = q.lower()
    return [it for it in items if needle in it.lower()]


def get_run_or_raise(domain: str, run_id: str) -> sqlite3.Row:
    row = query_one(
        "SELECT * FROM recon_runs WHERE domain = ? COLLATE NOCASE AND run_id = ?",
        (domain, run_id),
    )
    if row is None:
        raise LookupError(f"no run {run_id!r} found for domain {domain!r}")
    return row


def get_latest_run_or_raise(domain: str) -> sqlite3.Row:
    row = query_one(
        """
        SELECT * FROM recon_runs
        WHERE domain = ? COLLATE NOCASE
        ORDER BY run_date DESC, run_id DESC
        LIMIT 1
        """,
        (domain,),
    )
    if row is None:
        raise LookupError(f"no runs found for domain {domain!r}")
    return row


def resolve_run(domain: str, run_id: Optional[str]) -> sqlite3.Row:
    """run_id=None means "latest run for this domain" — every tool below
    that takes a run_id accepts the omission so a caller doesn't have to
    round-trip through list_runs()/get_target() first just to find out
    what the most recent run_id is."""
    if run_id:
        return get_run_or_raise(domain, run_id)
    return get_latest_run_or_raise(domain)


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------


@mcp.tool()
def list_targets() -> list[dict]:
    """List every target domain collector has ever ingested a run for,
    each with its latest run's headline numbers (subdomains, IPs, URLs,
    findings by severity). Use this first to discover what's available
    before calling get_target/list_runs/get_artifact with a specific
    domain."""
    rows = query(
        """
        SELECT * FROM latest_run
        ORDER BY (findings_critical * 100 + findings_high * 10 + js_secrets) DESC,
                 run_date DESC
        """
    )
    return [row_to_dict(r) for r in rows]


@mcp.tool()
def get_target(domain: str) -> dict:
    """Get one target's profile: its `targets` row (first_seen,
    scope_notes) plus its full run history (every `recon_runs` row for
    this domain, newest first). Raises if the domain was never
    ingested."""
    target = query_one("SELECT * FROM targets WHERE domain = ? COLLATE NOCASE", (domain,))
    if target is None:
        raise LookupError(f"no target found for domain {domain!r}")
    runs = query(
        "SELECT * FROM recon_runs WHERE domain = ? COLLATE NOCASE ORDER BY run_date DESC, run_id DESC",
        (domain,),
    )
    return {
        "target": row_to_dict(target),
        "runs": [row_to_dict(r) for r in runs],
    }


@mcp.tool()
def list_runs(
    domain: Optional[str] = None,
    mode: Optional[str] = None,
    page: int = 1,
    per_page: int = 25,
) -> dict:
    """List recon runs across all targets (or filtered to one domain
    and/or one mode — e.g. "recon", "webapp-enum", "url"). Paginated;
    returns {rows, total, page, pages, per_page}. Use this to browse
    run history without knowing a specific run_id up front."""
    where = []
    params: list = []
    if domain:
        where.append("domain LIKE ? COLLATE NOCASE")
        params.append(f"%{domain}%")
    if mode:
        where.append("mode = ?")
        params.append(mode)
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    per_page = max(min(per_page, 200), 1)
    page = max(page, 1)
    offset = (page - 1) * per_page

    total = query_one(f"SELECT COUNT(*) AS c FROM recon_runs {where_sql}", tuple(params))["c"]
    pages = max((total + per_page - 1) // per_page, 1) if total else 1
    page = min(page, pages)
    offset = (page - 1) * per_page

    rows = query(
        f"""
        SELECT * FROM recon_runs
        {where_sql}
        ORDER BY run_date DESC, run_id DESC
        LIMIT ? OFFSET ?
        """,
        tuple(params) + (per_page, offset),
    )
    return {
        "rows": [row_to_dict(r) for r in rows],
        "total": total,
        "page": page,
        "pages": pages,
        "per_page": per_page,
    }


@mcp.tool()
def get_run(domain: str, run_id: Optional[str] = None) -> dict:
    """Get one run's full `recon_runs` row (counts, timestamps, status,
    report_dir, llm_prompt_path). Omit run_id to get the most recent run
    for this domain. Raises if the domain or run_id doesn't exist."""
    return row_to_dict(resolve_run(domain, run_id))


@mcp.tool()
def list_artifact_kinds() -> list[dict]:
    """List every artifact kind get_artifact() can fetch — the slug to
    pass as `kind`, its human label, and the underlying filename under
    report_dir. Call this once to discover what's available instead of
    guessing kind names."""
    return [
        {"kind": k, "label": v["label"], "file": v["file"]}
        for k, v in ARTIFACT_KINDS.items()
    ]


@mcp.tool()
def get_artifact(
    domain: str,
    kind: str,
    run_id: Optional[str] = None,
    q: Optional[str] = None,
    page: int = 1,
    per_page: int = 200,
) -> dict:
    """Fetch the lines of one artifact file for a run (e.g. kind=
    "subdomains_alive" for the live-subdomain list, kind="webapp_consolidated"
    for the deduped URL list — see list_artifact_kinds() for the full set).
    Optional `q` does a case-insensitive substring filter before
    paginating. Omit run_id for the domain's latest run. Returns
    {kind, label, run_id, items, total, unfiltered_total, page, pages,
    per_page, file_exists}."""
    spec = ARTIFACT_KINDS.get(kind)
    if spec is None:
        raise ValueError(f"unknown artifact kind {kind!r} — call list_artifact_kinds() for the valid set")

    run = resolve_run(domain, run_id)
    path = safe_report_path(run["report_dir"], spec["file"])
    items = read_lines(path, skip_comments=spec.get("skip_comments", False))

    filtered = filter_substring(items, q.strip()) if q else items
    per_page = max(min(per_page, 1000), 1)
    page_items, total, pages = paginate(filtered, max(page, 1), per_page)

    return {
        "kind": kind,
        "label": spec["label"],
        "domain": run["domain"],
        "run_id": run["run_id"],
        "items": page_items,
        "total": total,
        "unfiltered_total": len(items),
        "page": page,
        "pages": pages,
        "per_page": per_page,
        "file_exists": path.is_file(),
    }


@mcp.tool()
def list_raw_file_kinds() -> list[dict]:
    """List every raw-file kind get_raw_file() can fetch — scan/tool
    output that isn't worth a dedicated parser (nmap, Shodan, the LLM
    prompt, precomputed diffs)."""
    return [
        {"kind": k, "label": v["label"], "path": "/".join(v["path"])}
        for k, v in RAW_FILES.items()
    ]


@mcp.tool()
def get_raw_file(
    domain: str,
    kind: str,
    run_id: Optional[str] = None,
    max_lines: int = 2000,
) -> dict:
    """Fetch a whitelisted raw file verbatim (see list_raw_file_kinds()
    for the valid `kind` values) — e.g. kind="nmap" for the nmap scan
    output, kind="llm_prompt" for the bundled LLM analysis prompt built
    for this run. Content is clipped to `max_lines` (full file always
    stays on disk; this just protects the response size). Returns
    {kind, label, run_id, content, missing, truncated, total_lines}."""
    spec = RAW_FILES.get(kind)
    if spec is None:
        raise ValueError(f"unknown raw file kind {kind!r} — call list_raw_file_kinds() for the valid set")

    run = resolve_run(domain, run_id)
    path = safe_report_path(run["report_dir"], *spec["path"])

    if not path.is_file():
        return {
            "kind": kind, "label": spec["label"], "domain": run["domain"], "run_id": run["run_id"],
            "content": "", "missing": True, "truncated": False, "total_lines": 0,
        }

    max_lines = max(min(max_lines, 20000), 1)
    lines: list[str] = []
    truncated = False
    total_lines = 0
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for i, raw in enumerate(fh, start=1):
            total_lines = i
            if i <= max_lines:
                lines.append(raw.rstrip("\n").rstrip("\r"))
            else:
                truncated = True
    return {
        "kind": kind, "label": spec["label"], "domain": run["domain"], "run_id": run["run_id"],
        "content": "\n".join(lines), "missing": False,
        "truncated": truncated, "total_lines": total_lines,
    }


@mcp.tool()
def get_findings(
    domain: str,
    run_id: Optional[str] = None,
    severity: Optional[list[str]] = None,
    q: Optional[str] = None,
    page: int = 1,
    per_page: int = 100,
) -> dict:
    """Get nuclei findings for a run (merges nuclei_scan.result and
    nuclei_web_fuzzing.result), sorted critical-first. `severity` filters
    to a subset (e.g. ["critical", "high"]); `q` does a case-insensitive
    substring match against the template id and URL. Omit run_id for
    the domain's latest run. Returns {run_id, findings, counts (per
    severity), total, page, pages, per_page}."""
    run = resolve_run(domain, run_id)

    findings_all: list[dict] = []
    for fname in ("nuclei_scan.result", "nuclei_web_fuzzing.result"):
        fpath = safe_report_path(run["report_dir"], "scan", "nuclei", fname)
        for f in parse_nuclei(fpath):
            f["source"] = fname
            findings_all.append(f)

    sev_filter = {s.lower() for s in (severity or []) if s}
    if sev_filter:
        findings_all = [f for f in findings_all if f["severity"] in sev_filter]

    if q:
        needle = q.strip().lower()
        findings_all = [
            f for f in findings_all
            if needle in f["template"].lower() or needle in f["url"].lower()
        ]

    sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4, "unknown": 5}
    findings_all.sort(key=lambda f: (sev_order.get(f["severity"], 9), f["template"]))

    counts = {k: 0 for k in ("critical", "high", "medium", "low", "info", "unknown")}
    for f in findings_all:
        counts[f["severity"]] = counts.get(f["severity"], 0) + 1

    per_page = max(min(per_page, 500), 1)
    page_items, total, pages = paginate(findings_all, max(page, 1), per_page)

    return {
        "domain": run["domain"],
        "run_id": run["run_id"],
        "findings": page_items,
        "counts": counts,
        "total": total,
        "page": page,
        "pages": pages,
        "per_page": per_page,
    }


@mcp.tool()
def diff_runs(domain: str, run_from: str, run_to: str) -> dict:
    """Compare two runs of the same domain across subdomains, IPs,
    consolidated URLs, vhosts, and emails: what's new (added) and
    what's gone (removed) in `run_to` relative to `run_from`, plus how
    many lines stayed the same (common_count). Runs are reordered
    chronologically if passed backwards. Both run_from and run_to must
    be run_ids that exist for this domain."""
    if run_from == run_to:
        raise ValueError("run_from and run_to must be different runs")

    a = get_run_or_raise(domain, run_from)
    b = get_run_or_raise(domain, run_to)
    if (a["run_date"] or "") > (b["run_date"] or ""):
        a, b = b, a

    diffable = [
        ("subdomains_alive", "Alive subdomains", "domains_alive.txt"),
        ("subdomains_found", "All subdomains", "domains_found.txt"),
        ("webapp_consolidated", "Consolidated URLs", "webapp_consolidated.txt"),
        ("ips", "IPs", "infra_ipv4.txt"),
        ("vhosts_strong", "vhosts (/etc/hosts)", "etc_hosts_file.txt"),
        ("emails", "Emails", "email_recon.txt"),
    ]
    sections = []
    for slug, label, fname in diffable:
        a_set = set(read_lines(safe_report_path(a["report_dir"], fname)))
        b_set = set(read_lines(safe_report_path(b["report_dir"], fname)))
        added = sorted(b_set - a_set)
        removed = sorted(a_set - b_set)
        if not added and not removed:
            continue
        sections.append({
            "slug": slug,
            "label": label,
            "added": added,
            "removed": removed,
            "added_count": len(added),
            "removed_count": len(removed),
            "common_count": len(a_set & b_set),
        })

    return {
        "domain": domain,
        "from_run_id": a["run_id"],
        "to_run_id": b["run_id"],
        "sections": sections,
    }


@mcp.tool()
def health() -> dict:
    """Cheap liveness/config check: confirms the SQLite DB opens and
    reports the resolved DB_PATH/OUTPUT_DIR this server is actually
    using — useful to sanity-check COLLECTOR_DB/COLLECTOR_OUTPUT_DIR
    before debugging anything else."""
    try:
        n = query_one("SELECT COUNT(*) AS c FROM targets")["c"]
        return {"ok": True, "targets": n, "db": str(DB_PATH), "output_dir": str(OUTPUT_DIR)}
    except Exception as exc:
        return {"ok": False, "error": str(exc), "db": str(DB_PATH), "output_dir": str(OUTPUT_DIR)}


if __name__ == "__main__":
    mcp.run(transport=TRANSPORT)
