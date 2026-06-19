"""
collector app-report — Flask + HTMX UI over collector-results-db.

Read-only by design: the recon flow is the only writer (via db_usage),
this app just renders. Single-process gunicorn worker is enough for the
expected audience (operator + a couple of viewers).

Configuration is taken from environment variables populated by
start_app_report() in functions/utils.sh, which itself sources
collector.cfg. Keeping the contract that simple means there's no second
config file to maintain.

Two read sources are stitched together:
  1. collector-results-db (SQLite, via mode=ro URI) — counts and trends.
  2. report_dir/*.txt files written by the recon flow — drill-down
     content (the actual subdomains, URLs, findings, etc). The DB stores
     report_dir paths but not their contents; we open them lazily, with
     path-traversal guards rooted at COLLECTOR_OUTPUT_DIR.
"""

from __future__ import annotations

import os
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

from flask import Flask, abort, g, render_template, request

DB_PATH = Path(os.environ.get("COLLECTOR_DB", "collector-results-db")).resolve()
OUTPUT_DIR = Path(os.environ.get("COLLECTOR_OUTPUT_DIR", ".")).resolve()

app = Flask(__name__)


# ---------------------------------------------------------------------------
# DB plumbing
# ---------------------------------------------------------------------------


def get_db() -> sqlite3.Connection:
    """One read-only connection per request, cached on flask.g."""
    if "db" not in g:
        if not DB_PATH.exists():
            abort(503, description=f"collector DB not found at {DB_PATH}")
        # uri=True + mode=ro keeps the writer (db_usage) safe even if the
        # web app misbehaves — SQLite refuses any write through this handle.
        g.db = sqlite3.connect(
            f"file:{DB_PATH}?mode=ro",
            uri=True,
            detect_types=sqlite3.PARSE_DECLTYPES,
        )
        g.db.row_factory = sqlite3.Row
    return g.db


@app.teardown_appcontext
def close_db(_exception):
    db = g.pop("db", None)
    if db is not None:
        db.close()


def query(sql: str, params: tuple = ()) -> list[sqlite3.Row]:
    return get_db().execute(sql, params).fetchall()


def query_one(sql: str, params: tuple = ()) -> sqlite3.Row | None:
    return get_db().execute(sql, params).fetchone()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


SEVERITY_KEYS = ("critical", "high", "medium", "low", "info")


def fmt_dt(value: str | None) -> str:
    if not value:
        return "—"
    # SQLite stores ISO 8601 strings; render them in the operator's local
    # timezone for readability.
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone().strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return value


app.jinja_env.filters["fmt_dt"] = fmt_dt


@app.context_processor
def inject_globals():
    """Make db_path available to every template (the footer in base.html
    used to read it only on the index route, so other pages rendered the
    placeholder text instead of the real path)."""
    return {"db_path": str(DB_PATH)}


# ---------------------------------------------------------------------------
# Filesystem access (drill-down into report_dir)
# ---------------------------------------------------------------------------


def safe_report_path(report_dir: str | None, *parts: str) -> Path:
    """Resolve `report_dir` joined with `parts` and guarantee the result
    stays under COLLECTOR_OUTPUT_DIR. Refuses anything containing '..'
    or a leading slash on the suffix parts. 404s on traversal attempts.

    The DB stores absolute paths to report_dir (set by collector at run
    time), so we trust the prefix only inasmuch as it lives under
    OUTPUT_DIR. A misconfigured deployment where output_dir != the dir
    used at scan time will fail safely with 404 instead of leaking
    arbitrary files.
    """
    if not report_dir:
        abort(404)
    base = Path(report_dir).resolve()
    try:
        base.relative_to(OUTPUT_DIR)
    except ValueError:
        # report_dir lives outside OUTPUT_DIR — refuse rather than serve.
        abort(404)
    for part in parts:
        if not part or part.startswith("/") or ".." in Path(part).parts:
            abort(404)
    final = (base.joinpath(*parts)).resolve()
    try:
        final.relative_to(OUTPUT_DIR)
    except ValueError:
        abort(404)
    return final


# Whitelisted artifact kinds: maps URL slug -> (relative path under
# report_dir, human label, presentation hint). Only kinds in this map
# can be served, so adding a new file type to the dashboard is an
# explicit decision rather than a generic file browser.
ARTIFACT_KINDS: dict[str, dict] = {
    # Subdomain universe
    "subdomains_alive":            {"file": "domains_alive.txt",                "label": "Subdomains alive",          "hint": "host"},
    "subdomains_found":            {"file": "domains_found.txt",                "label": "All subdomains discovered", "hint": "host"},
    "subdomains_aliases":          {"file": "domains_aliases.txt",              "label": "Subdomain aliases (CNAME)", "hint": "host"},
    "subdomains_thirdpart":        {"file": "domains_thirdpart.txt",            "label": "Third-party delegations",   "hint": "host"},
    "subdomains_without_resolution": {"file": "domains_without_resolution.txt", "label": "Subdomains w/o resolution", "hint": "host"},
    "subdomains_excluded":         {"file": "domains_excluded.txt",             "label": "Excluded subdomains",       "hint": "host"},
    "subdomains_infrastructure":   {"file": "domains_infrastructure.txt",       "label": "Infrastructure (A/AAAA/MX/NS)", "hint": "raw"},
    "subdomains_internal_ipv4":    {"file": "domains_internal_ipv4.txt",        "label": "Internal IPv4 (RFC1918)",   "hint": "raw"},
    "subdomains_external_ipv4":    {"file": "domains_external_ipv4.txt",        "label": "External IPv4",             "hint": "raw"},
    "subdomains_external_ipv6":    {"file": "domains_external_ipv6.txt",        "label": "External IPv6",             "hint": "raw"},
    "zone_transfer":               {"file": "zone_transfer.txt",                "label": "Zone transfer (AXFR)",      "hint": "raw"},
    # Infra / IPs
    "ips":                         {"file": "infra_ipv4.txt",                   "label": "IPs",                       "hint": "ip"},
    "infra_as":                    {"file": "infra_as.txt",                     "label": "AS / BGP info",             "hint": "raw"},
    "infra_blocks":                {"file": "infra_blocks.txt",                 "label": "Netblocks",                 "hint": "raw"},
    # Web
    "webapp_urls":                 {"file": "webapp_urls.txt",                  "label": "Webapp URLs",               "hint": "url"},
    "robots_urls":                 {"file": "robots_urls.txt",                  "label": "robots.txt URLs",           "hint": "url"},
    "vhosts_strong":               {"file": "vhost_subdomains.txt",             "label": "vhosts (STRONG)",           "hint": "host"},
    "vhosts_weak":                 {"file": "vhost_subdomains_weak.txt",        "label": "vhosts (WEAK)",             "hint": "host"},
    # Recon
    "emails":                      {"file": "email_recon.txt",                  "label": "Emails",                    "hint": "host"},
    "js_secrets":                  {"file": "webapp_js_secrets.txt",            "label": "JS secrets",                "hint": "comment"},
    "js_params":                   {"file": "webapp_js_params.txt",             "label": "JS params (DOM sinks)",     "hint": "comment"},
}


def _read_lines(path: Path, *, skip_comments: bool = False) -> list[str]:
    """Read a text file as a list of stripped lines. Missing file → []."""
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


# Nuclei output looks like:
#   [template-id] [proto] [severity] http://host/path [extras]
# severity is the third bracket-delimited token; everything after the
# closing `] ` of severity is the URL plus optional extras.
_NUCLEI_RE = re.compile(
    r"^\[(?P<template>[^\]]+)\]\s+\[(?P<proto>[^\]]+)\]\s+\[(?P<severity>[^\]]+)\]\s+(?P<rest>.+)$"
)


def parse_nuclei(path: Path) -> list[dict]:
    """Parse a nuclei result file into a list of finding dicts. Lines
    that don't match the template are kept as `severity='unknown'` so
    the operator can still see them surfacing — better than silently
    dropping rows that nuclei format-changes might break."""
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
                out.append({"template": "—", "proto": "—", "severity": "unknown", "url": line, "raw": line})
                continue
            rest = m.group("rest").strip()
            # The URL is the first whitespace-delimited token of `rest`;
            # what follows is template-specific extras (matched-at,
            # extracted-from, etc).
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
    """Return (page_slice, total, pages). 1-indexed pages."""
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


def _get_run_or_404(domain: str, run_id: str):
    row = query_one(
        """
        SELECT * FROM recon_runs
        WHERE domain = ? COLLATE NOCASE AND run_id = ?
        """,
        (domain, run_id),
    )
    if row is None:
        abort(404)
    return row


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/")
def index():
    """Dashboard: KPIs + per-target latest run."""
    targets_total = query_one("SELECT COUNT(*) AS c FROM targets")["c"]
    runs_total = query_one("SELECT COUNT(*) AS c FROM recon_runs")["c"]

    # Aggregates from latest_run (one row per target = current state).
    totals = query_one(
        """
        SELECT
            COALESCE(SUM(subdomains), 0)        AS subdomains,
            COALESCE(SUM(subdomains_alive), 0)  AS subdomains_alive,
            COALESCE(SUM(ips), 0)               AS ips,
            COALESCE(SUM(webapp_urls), 0)       AS webapp_urls,
            COALESCE(SUM(emails), 0)            AS emails,
            COALESCE(SUM(js_secrets), 0)        AS js_secrets,
            COALESCE(SUM(js_params), 0)         AS js_params,
            COALESCE(SUM(findings_critical), 0) AS findings_critical,
            COALESCE(SUM(findings_high), 0)     AS findings_high,
            COALESCE(SUM(findings_medium), 0)   AS findings_medium,
            COALESCE(SUM(findings_low), 0)      AS findings_low,
            COALESCE(SUM(findings_info), 0)     AS findings_info
        FROM latest_run
        """
    )

    rows = query(
        """
        SELECT * FROM latest_run
        ORDER BY (findings_critical * 100 + findings_high * 10 + js_secrets) DESC,
                 run_date DESC
        """
    )

    return render_template(
        "index.html",
        targets_total=targets_total,
        runs_total=runs_total,
        totals=totals,
        rows=rows,
    )


@app.route("/targets/<domain>")
def target_detail(domain: str):
    """Per-target page: timeline + most recent run breakdown."""
    target = query_one(
        "SELECT * FROM targets WHERE domain = ? COLLATE NOCASE", (domain,)
    )
    if target is None:
        abort(404)

    runs = query(
        """
        SELECT * FROM recon_runs
        WHERE domain = ? COLLATE NOCASE
        ORDER BY run_date DESC, run_id DESC
        """,
        (domain,),
    )
    if not runs:
        abort(404)

    latest = runs[0]

    # Trend series for the chart (oldest → newest).
    trend = list(reversed(runs))
    chart = {
        "labels": [r["run_date"] or r["run_id"] for r in trend],
        "subdomains": [r["subdomains"] or 0 for r in trend],
        "ips": [r["ips"] or 0 for r in trend],
        "webapp_urls": [r["webapp_urls"] or 0 for r in trend],
        "findings_high": [r["findings_high"] or 0 for r in trend],
        "findings_critical": [r["findings_critical"] or 0 for r in trend],
        "js_secrets": [r["js_secrets"] or 0 for r in trend],
    }

    return render_template(
        "target.html",
        target=target,
        latest=latest,
        runs=runs,
        chart=chart,
    )


@app.route("/runs")
def runs():
    """Searchable / filterable run table — designed for HTMX partials."""
    domain = request.args.get("domain", "").strip()
    mode = request.args.get("mode", "").strip()
    page = max(int(request.args.get("page", "1") or 1), 1)
    per_page = 25
    offset = (page - 1) * per_page

    where = []
    params: list = []
    if domain:
        where.append("domain LIKE ? COLLATE NOCASE")
        params.append(f"%{domain}%")
    if mode:
        where.append("mode = ?")
        params.append(mode)
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""

    rows = query(
        f"""
        SELECT * FROM recon_runs
        {where_sql}
        ORDER BY run_date DESC, run_id DESC
        LIMIT ? OFFSET ?
        """,
        tuple(params) + (per_page, offset),
    )
    total = query_one(
        f"SELECT COUNT(*) AS c FROM recon_runs {where_sql}", tuple(params)
    )["c"]

    modes = [r["mode"] for r in query("SELECT DISTINCT mode FROM recon_runs WHERE mode IS NOT NULL ORDER BY mode")]

    template = "_runs_table.html" if request.headers.get("HX-Request") else "runs.html"
    return render_template(
        template,
        rows=rows,
        total=total,
        page=page,
        per_page=per_page,
        domain=domain,
        mode=mode,
        modes=modes,
    )


# ---------------------------------------------------------------------------
# Drill-down routes — read content out of report_dir/*.txt for a given run
# ---------------------------------------------------------------------------


@app.route("/targets/<domain>/<run_id>/<kind>")
def artifact(domain: str, run_id: str, kind: str):
    """Paginated, filterable view of a single artifact file (e.g. the
    list of alive subdomains for a specific run). The set of supported
    `kind` slugs is the keys of ARTIFACT_KINDS — anything else is 404."""
    spec = ARTIFACT_KINDS.get(kind)
    if spec is None:
        abort(404)

    run = _get_run_or_404(domain, run_id)
    path = safe_report_path(run["report_dir"], spec["file"])

    skip_comments = spec.get("hint") == "comment"
    items = _read_lines(path, skip_comments=skip_comments)

    q = request.args.get("q", "").strip()
    filtered = filter_substring(items, q) if q else items

    page = max(int(request.args.get("page", "1") or 1), 1)
    per_page = int(request.args.get("per_page", "100") or 100)
    per_page = max(min(per_page, 500), 25)
    page_items, total, pages = paginate(filtered, page, per_page)

    template = "_artifact_table.html" if request.headers.get("HX-Request") else "artifact.html"
    return render_template(
        template,
        domain=run["domain"],
        run=run,
        kind=kind,
        spec=spec,
        items=page_items,
        total=total,
        unfiltered_total=len(items),
        page=page,
        pages=pages,
        per_page=per_page,
        q=q,
        file_exists=path.is_file(),
        file_path=str(path),
    )


@app.route("/targets/<domain>/<run_id>/findings")
def findings(domain: str, run_id: str):
    """Nuclei findings — both nuclei_scan.result and nuclei_web_fuzzing.result
    parsed and merged. Supports filtering by severity (multi-select) and
    free-text search across template/url."""
    run = _get_run_or_404(domain, run_id)
    base = safe_report_path(run["report_dir"])

    findings_all: list[dict] = []
    for fname in ("nuclei_scan.result", "nuclei_web_fuzzing.result"):
        # safe_report_path validates each path individually
        fpath = safe_report_path(run["report_dir"], "scan", "nuclei", fname)
        for f in parse_nuclei(fpath):
            f["source"] = fname
            findings_all.append(f)

    # Severity filter — accept ?severity=critical&severity=high...
    sev_filter = set(s.lower() for s in request.args.getlist("severity") if s)
    if sev_filter:
        findings_all = [f for f in findings_all if f["severity"] in sev_filter]

    q = request.args.get("q", "").strip()
    if q:
        needle = q.lower()
        findings_all = [
            f for f in findings_all
            if needle in f["template"].lower() or needle in f["url"].lower()
        ]

    # Sort: severity buckets first (crit > high > med > low > info > unknown),
    # then by template name to keep related findings adjacent.
    sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4, "unknown": 5}
    findings_all.sort(key=lambda f: (sev_order.get(f["severity"], 9), f["template"]))

    page = max(int(request.args.get("page", "1") or 1), 1)
    per_page = 100
    page_items, total, pages = paginate(findings_all, page, per_page)

    # Per-severity tallies for the chip row at the top of the page.
    counts = {k: 0 for k in SEVERITY_KEYS}
    counts["unknown"] = 0
    for f in findings_all:
        counts[f["severity"]] = counts.get(f["severity"], 0) + 1

    template = "_findings_table.html" if request.headers.get("HX-Request") else "findings.html"
    return render_template(
        template,
        domain=run["domain"],
        run=run,
        findings=page_items,
        counts=counts,
        sev_filter=sev_filter,
        q=q,
        page=page,
        pages=pages,
        total=total,
        base_dir=str(base),
    )


# Files we consciously expose under `/raw/`. Anything else 404s — this
# is not a generic file browser. The intent is to give the operator
# read-only access to artifacts that aren't worth their own parser.
RAW_FILES: dict[str, dict] = {
    "nmap":           {"path": ("nmap_scan.txt",),                    "label": "nmap scan"},
    "shodan":         {"path": ("scan", "shodan", "shodan_scan.txt"), "label": "Shodan scan"},
    "llm_prompt":     {"path": ("llm-prompt.txt",),                   "label": "LLM prompt bundle"},
    "domains_diff":   {"path": ("domains_diff.txt",),                 "label": "Subdomains diff"},
    "infra_ipv4_diff":{"path": ("infra_ipv4_diff.txt",),              "label": "Infra IPv4 diff"},
    "webapp_urls_diff":{"path": ("webapp_urls_diff.txt",),            "label": "Webapp URLs diff"},
    "vhost_diff":     {"path": ("vhost_subdomains_diff.txt",),        "label": "vhosts diff"},
    "email_diff":     {"path": ("email_recon_diff.txt",),             "label": "Emails diff"},
    "nuclei_diff":    {"path": ("scan", "nuclei", "nuclei_scan_diff.txt"), "label": "Nuclei diff"},
}

# How many lines we'll render at most in one chunk. nmap output for a
# /16 scan can be tens of thousands of lines; clipping keeps the page
# responsive. The full file is always available on disk.
RAW_MAX_LINES = 5000


@app.route("/targets/<domain>/<run_id>/raw/<kind>")
def raw_file(domain: str, run_id: str, kind: str):
    """Plain-text view of a whitelisted file. Pure rendering — no
    parsing — wrapped in `<pre>` with monospace and basic line numbers."""
    spec = RAW_FILES.get(kind)
    if spec is None:
        abort(404)
    run = _get_run_or_404(domain, run_id)
    path = safe_report_path(run["report_dir"], *spec["path"])

    if not path.is_file():
        return render_template(
            "raw.html",
            domain=run["domain"], run=run, kind=kind, spec=spec,
            content="", missing=True, path=str(path), truncated=False, total_lines=0,
        )

    lines: list[str] = []
    truncated = False
    total_lines = 0
    with path.open("r", encoding="utf-8", errors="replace") as fh:
        for i, raw in enumerate(fh, start=1):
            total_lines = i
            if i <= RAW_MAX_LINES:
                lines.append(raw.rstrip("\n").rstrip("\r"))
            else:
                truncated = True
    content = "\n".join(lines)
    return render_template(
        "raw.html",
        domain=run["domain"], run=run, kind=kind, spec=spec,
        content=content, missing=False, path=str(path),
        truncated=truncated, total_lines=total_lines, max_lines=RAW_MAX_LINES,
    )


@app.route("/targets/<domain>/diff")
def diff_runs(domain: str):
    """Compare two runs of the same target. For artifacts the collector
    already diff'd to disk (subdomains, IPs, URLs, vhosts, emails) we
    show those files verbatim. For artifacts without a precomputed
    diff, we compute a Python set diff on-the-fly. Both runs must
    belong to `domain`."""
    from_id = request.args.get("from", "").strip()
    to_id = request.args.get("to", "").strip()
    if not from_id or not to_id:
        abort(404, description="diff requires from and to query params")
    if from_id == to_id:
        abort(404, description="from and to must be different runs")

    target = query_one(
        "SELECT * FROM targets WHERE domain = ? COLLATE NOCASE", (domain,)
    )
    if target is None:
        abort(404)

    a = _get_run_or_404(domain, from_id)
    b = _get_run_or_404(domain, to_id)

    # Order chronologically — diff means "what changed between older
    # (from) and newer (to)". If the operator picked them backwards,
    # swap so the numbers make sense.
    if (a["run_date"] or "") > (b["run_date"] or ""):
        a, b = b, a

    sections = []
    # The artifacts we can usefully diff: each entry is (slug, label, file).
    diffable = [
        ("subdomains_alive", "Alive subdomains", "domains_alive.txt"),
        ("subdomains_found", "All subdomains",   "domains_found.txt"),
        ("webapp_urls",      "Webapp URLs",      "webapp_urls.txt"),
        ("ips",              "IPs",              "infra_ipv4.txt"),
        ("vhosts_strong",    "vhosts (STRONG)",  "vhost_subdomains.txt"),
        ("vhosts_weak",      "vhosts (WEAK)",    "vhost_subdomains_weak.txt"),
        ("emails",           "Emails",           "email_recon.txt"),
    ]
    for slug, label, fname in diffable:
        a_path = safe_report_path(a["report_dir"], fname)
        b_path = safe_report_path(b["report_dir"], fname)
        a_set = set(_read_lines(a_path))
        b_set = set(_read_lines(b_path))
        added = sorted(b_set - a_set)
        removed = sorted(a_set - b_set)
        if not added and not removed:
            continue
        sections.append({
            "slug": slug, "label": label, "file": fname,
            "added": added[:200],   # cap per-section to keep page sane
            "removed": removed[:200],
            "added_count": len(added),
            "removed_count": len(removed),
            "common_count": len(a_set & b_set),
        })

    return render_template(
        "diff.html",
        target=target, a=a, b=b, sections=sections,
    )


@app.route("/health")
def health():
    """Cheap liveness probe: open the DB and count targets."""
    try:
        n = query_one("SELECT COUNT(*) AS c FROM targets")["c"]
        return {"ok": True, "targets": n, "db": str(DB_PATH)}
    except Exception as exc:  # pragma: no cover
        return {"ok": False, "error": str(exc)}, 503


@app.errorhandler(404)
def not_found(_):
    return render_template("error.html", code=404, message="Not found"), 404


@app.errorhandler(503)
def unavailable(err):
    return render_template("error.html", code=503, message=str(err.description)), 503


if __name__ == "__main__":
    # Dev-only entrypoint. Production is gunicorn launched by
    # start_app_report() in functions/utils.sh.
    app.run(
        host=os.environ.get("APP_REPORT_HOST", "127.0.0.1"),
        port=int(os.environ.get("APP_REPORT_PORT", "8000")),
        debug=False,
    )
