"""
collector app-report — Flask + HTMX UI over collector-results-db.

Read-only by design: the recon flow is the only writer (via db_usage),
this app just renders. Single-process gunicorn worker is enough for the
expected audience (operator + a couple of viewers).

Configuration is taken from environment variables populated by
start_app_report() in functions/utils.sh, which itself sources
collector.cfg. Keeping the contract that simple means there's no second
config file to maintain.
"""

from __future__ import annotations

import os
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
