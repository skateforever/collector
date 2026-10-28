#!/usr/bin/env python3
"""
js_api_extractor.py — Reconstructs API calls (HTTP method, URL expression,
and request body) found in one or more JavaScript files, by locating
common HTTP client call shapes (Angular HttpClient, axios, fetch,
jQuery.ajax) and extracting their arguments via paren/brace-balanced,
string-aware scanning (not a full JS parser — same philosophy as
js_deobfuscator.py's structural detectors).

Meant to run on de-obfuscated JS (see js_deobfuscator.py) so verbs/paths
hidden behind an obfuscator's decoder (e.g. this.http[decoder(0x1f1)](...))
are already literal strings by the time this script sees them.

This is a best-effort, STATIC reconstruction for manual triage. It never
executes any code. A URL or body that is itself an expression (e.g.
`this.baseUrl + '/foo'` or `JSON.stringify(data)`) is reported as raw
source text — unresolvable sub-expressions are rendered as "<expr>"
placeholders in OpenAPI/Postman output, never guessed at.

Uso:
    python3 js_api_extractor.py arquivo1.js [arquivo2.js ...]
    python3 js_api_extractor.py *.js --relatorio-json calls.json
    python3 js_api_extractor.py *.js --openapi api.yaml --postman collection.json

OpenAPI/Postman output needs no third-party packages: YAML is emitted by
a minimal dependency-free emitter (see _yaml_dump), in keeping with
js_deobfuscator.py's stdlib-only policy.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

HTTP_VERBS = ("get", "post", "put", "delete", "patch", "head", "options")
_VERBS_ALT = "|".join(HTTP_VERBS)


@dataclass
class ApiCall:
    file: str
    line: int
    client: str
    method: str
    url: str
    body: str | None

    def to_dict(self) -> dict:
        return {
            "file": self.file,
            "line": self.line,
            "client": self.client,
            "method": self.method,
            "url": self.url,
            "body": self.body,
        }


def line_of(text: str, idx: int) -> int:
    return text.count("\n", 0, idx) + 1


def find_matching(text: str, open_idx: int, open_ch: str, close_ch: str) -> int | None:
    """From text[open_idx] == open_ch, find the index of the matching
    close_ch, tracking nesting depth and skipping over string/template
    literals (so a paren/brace inside a string doesn't throw off the
    count)."""
    depth = 0
    i = open_idx
    in_string: str | None = None
    n = len(text)
    while i < n:
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"', "`"):
            in_string = ch
            i += 1
            continue
        if ch == open_ch:
            depth += 1
        elif ch == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def split_top_level(text: str, sep: str) -> list[str]:
    """Split text on `sep` characters that sit at bracket-nesting depth 0
    and outside of string/template literals."""
    parts: list[str] = []
    depth = 0
    in_string: str | None = None
    start = 0
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == in_string:
                in_string = None
            i += 1
            continue
        if ch in ("'", '"', "`"):
            in_string = ch
        elif ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == sep and depth == 0:
            parts.append(text[start:i])
            start = i + 1
        i += 1
    parts.append(text[start:])
    return parts


def extract_call_args(text: str, paren_open_idx: int) -> list[str] | None:
    """text[paren_open_idx] must be '('. Returns the call's top-level
    arguments as raw source strings, or None if unbalanced."""
    close_idx = find_matching(text, paren_open_idx, "(", ")")
    if close_idx is None:
        return None
    inner = text[paren_open_idx + 1 : close_idx]
    return [a.strip() for a in split_top_level(inner, ",") if a.strip() != ""]


def parse_object_props(obj_text: str) -> dict[str, str]:
    """Best-effort parse of a {...} object literal's TOP-LEVEL key: value
    pairs. Keys are normalized (quotes/brackets stripped); values are kept
    as raw source text. Not a JSON parser — shorthand props and spreads are
    silently skipped rather than guessed at."""
    t = obj_text.strip()
    if t.startswith("{") and t.endswith("}"):
        t = t[1:-1]
    props: dict[str, str] = {}
    for part in split_top_level(t, ","):
        part = part.strip()
        if not part or part.startswith("..."):
            continue
        kv = split_top_level(part, ":")
        if len(kv) < 2:
            continue
        key = kv[0].strip().strip("'\"`[] ")
        value = ":".join(kv[1:]).strip()
        if key:
            props[key] = value
    return props


# ---------------------------------------------------------------------------
# Call-shape detectors.
# ---------------------------------------------------------------------------

# Angular HttpClient (or any "this.http"/"$http"/bare "http" service var).
# Covers both this.http.post(...) and the member-bracket form
# this.http["post"](...) that survives from obfuscated member-expression
# access once js_deobfuscator.py has resolved the decoder(0x..) call inside
# the brackets back to a literal string.
RE_HTTP_DOT = re.compile(r"\b((?:this\.)?\$?[Hh]ttp)\.(" + _VERBS_ALT + r")\s*\(")
RE_HTTP_BRACKET = re.compile(
    r"\b((?:this\.)?\$?[Hh]ttp)\[\s*['\"](" + _VERBS_ALT + r")['\"]\s*\]\s*\("
)
RE_AXIOS_VERB = re.compile(r"\baxios\.(" + _VERBS_ALT + r")\s*\(")
RE_AXIOS_CALL = re.compile(r"\baxios(?:\.request)?\s*\(")
RE_FETCH = re.compile(r"\bfetch\s*\(")
RE_JQUERY_AJAX = re.compile(r"\$\.ajax\s*\(")


def _calls_from_verb_regex(
    text: str, rx: re.Pattern, client: str, verb_group: int, file: str
) -> list[ApiCall]:
    calls: list[ApiCall] = []
    for m in rx.finditer(text):
        paren_idx = m.end() - 1
        args = extract_call_args(text, paren_idx)
        if args is None:
            continue
        method = m.group(verb_group).upper()
        url = args[0] if len(args) >= 1 else "<unknown>"
        body = args[1] if len(args) >= 2 else None
        calls.append(ApiCall(file, line_of(text, m.start()), client, method, url, body))
    return calls


def detect_http_client(text: str, file: str) -> list[ApiCall]:
    return _calls_from_verb_regex(
        text, RE_HTTP_DOT, "angular-http", 2, file
    ) + _calls_from_verb_regex(text, RE_HTTP_BRACKET, "angular-http", 2, file)


def detect_axios(text: str, file: str) -> list[ApiCall]:
    calls = _calls_from_verb_regex(text, RE_AXIOS_VERB, "axios", 1, file)

    for m in RE_AXIOS_CALL.finditer(text):
        paren_idx = m.end() - 1
        args = extract_call_args(text, paren_idx)
        if not args:
            continue
        first = args[0].strip()
        if first.startswith("{"):
            props = parse_object_props(first)
            method = props.get("method", "GET").strip("'\"`").upper()
            url = props.get("url", "<unknown>")
            body = props.get("data") or props.get("body")
        else:
            # axios(url[, config]) shorthand — defaults to GET.
            method = "GET"
            url = first
            body = None
            if len(args) >= 2:
                props = parse_object_props(args[1])
                method = props.get("method", method).strip("'\"`").upper()
                body = props.get("data") or props.get("body")
        calls.append(ApiCall(file, line_of(text, m.start()), "axios", method, url, body))
    return calls


def detect_fetch(text: str, file: str) -> list[ApiCall]:
    calls: list[ApiCall] = []
    for m in RE_FETCH.finditer(text):
        paren_idx = m.end() - 1
        args = extract_call_args(text, paren_idx)
        if not args:
            continue
        url = args[0]
        method = "GET"
        body = None
        if len(args) >= 2:
            props = parse_object_props(args[1])
            if "method" in props:
                method = props["method"].strip("'\"`").upper()
            body = props.get("body")
        calls.append(ApiCall(file, line_of(text, m.start()), "fetch", method, url, body))
    return calls


def detect_jquery_ajax(text: str, file: str) -> list[ApiCall]:
    calls: list[ApiCall] = []
    for m in RE_JQUERY_AJAX.finditer(text):
        paren_idx = m.end() - 1
        args = extract_call_args(text, paren_idx)
        if not args:
            continue
        props = parse_object_props(args[0])
        method = (props.get("type") or props.get("method") or "GET").strip("'\"`").upper()
        url = props.get("url", "<unknown>")
        body = props.get("data")
        calls.append(ApiCall(file, line_of(text, m.start()), "jquery-ajax", method, url, body))
    return calls


DETECTORS = [detect_http_client, detect_axios, detect_fetch, detect_jquery_ajax]


def extract_api_calls(text: str, file: str) -> list[ApiCall]:
    calls: list[ApiCall] = []
    for detector in DETECTORS:
        calls.extend(detector(text, file))
    calls.sort(key=lambda c: c.line)
    return calls


def process_files(paths: list[Path]) -> list[ApiCall]:
    calls: list[ApiCall] = []
    for path in paths:
        text = path.read_text(encoding="utf-8", errors="replace")
        calls.extend(extract_api_calls(text, str(path)))
    return calls


def imprimir_relatorio_humano(calls: list[ApiCall]) -> None:
    for c in calls:
        print("---")
        print(f"File: {c.file}:{c.line}")
        print(f"Client: {c.client}")
        print(f"Method: {c.method}")
        print(f"URL: {c.url}")
        print("Body:")
        print(c.body.strip() if c.body is not None else "(none)")
    if calls:
        print("---")


# ---------------------------------------------------------------------------
# URL expression -> path template / query params (for OpenAPI & Postman).
# ---------------------------------------------------------------------------

_RE_NUMBER = re.compile(r"^-?\d+(\.\d+)?$")
_IDENT_RE = re.compile(r"^[A-Za-z_$][A-Za-z0-9_$]*(\.[A-Za-z_$][A-Za-z0-9_$]*)*$")
_RE_TEMPLATE_VAR = re.compile(r"\$\{([^}]*)\}")


def _sanitize_param_name(expr: str, fallback_idx: int) -> str:
    e = expr.strip()
    if _IDENT_RE.match(e):
        return e.rsplit(".", 1)[-1]
    return f"param{fallback_idx}"


def js_value_to_example(expr: str):
    """Best-effort conversion of a JS expression (string literal, number,
    bool, null/undefined, object literal, array literal, or arbitrary
    expression) into a JSON-serializable Python value, for use as an
    OpenAPI/Postman example. Unresolvable expressions (variable refs,
    function calls, etc.) become a "<expr>" placeholder string so the
    example always stays valid JSON, never raw JS source."""
    e = expr.strip()
    if e == "":
        return None
    if (e[0] == e[-1] == "'") or (e[0] == e[-1] == '"'):
        return e[1:-1]
    if e[0] == e[-1] == "`":
        inner = e[1:-1]
        return _RE_TEMPLATE_VAR.sub(lambda m: f"<{m.group(1).strip()}>", inner)
    if e in ("true", "false"):
        return e == "true"
    if e in ("null", "undefined"):
        return None
    if _RE_NUMBER.match(e):
        return float(e) if "." in e else int(e)
    if e.startswith("{") and e.endswith("}"):
        return _object_literal_to_dict(e)
    if e.startswith("[") and e.endswith("]"):
        inner = e[1:-1]
        return [js_value_to_example(p) for p in split_top_level(inner, ",") if p.strip() != ""]
    # Bare identifier, member expression, function call, concatenation,
    # ternary, etc. — can't resolve statically, so surface it as a
    # readable placeholder instead of guessing a value.
    return f"<{e}>"


def _object_literal_to_dict(obj_text: str) -> dict:
    t = obj_text.strip()
    if t.startswith("{") and t.endswith("}"):
        t = t[1:-1]
    result: dict = {}
    for part in split_top_level(t, ","):
        part = part.strip()
        if not part or part.startswith("..."):
            continue
        kv = split_top_level(part, ":")
        if len(kv) < 2:
            # Shorthand property { id } -> { "id": "<id>" }
            key = part.strip().strip("'\"`[] ")
            if key:
                result[key] = f"<{key}>"
            continue
        key = kv[0].strip().strip("'\"`[] ")
        value_expr = ":".join(kv[1:]).strip()
        if key:
            result[key] = js_value_to_example(value_expr)
    return result


def body_expr_to_example(body: str | None):
    if body is None:
        return None
    b = body.strip()
    m = re.match(r"^JSON\.stringify\s*\((.*)\)$", b, re.DOTALL)
    if m:
        b = m.group(1).strip()
    return js_value_to_example(b)


def analyze_url(url_expr: str) -> dict:
    """Breaks a URL expression (possibly a '+'-concatenation of string
    literals and variables, or a template literal) into:
      - path_template: path only (host stripped, see 'host' below),
        OpenAPI-style '{param}' placeholders, query string stripped.
      - path_params: ordered list of param names used in path_template
      - query: dict of query-param-name -> example value (best effort)
      - host: hostname, if the expression resolves to an absolute
        "http(s)://host/..." URL; None for relative paths.
      - base_expr: the leading bare-identifier token (e.g. "this.baseUrl"),
        if the expression starts with one — these are near-always a fixed
        config prefix (baseUrl/apiRootUrl/environment.X), not route data,
        so they're reported separately rather than turned into a
        misleading "{baseUrl}" path parameter.
      - resolvable: False when there is no literal text ANYWHERE in the
        expression (e.g. the url is a bare variable like `endpoint`) —
        path_template is still a valid "/{param}" path in that case
        (never a bare "{param}", which isn't a legal OpenAPI path), just
        with zero real information in it.
    """
    tokens = split_top_level(url_expr.strip(), "+")
    literal_parts: list[str] = []
    path_params: list[str] = []
    has_literal = False
    param_counter = 0
    base_expr: str | None = None

    for idx, tok in enumerate(tokens):
        t = tok.strip()
        if not t:
            continue
        if (t[0] == t[-1] == "'") or (t[0] == t[-1] == '"'):
            literal_parts.append(t[1:-1])
            has_literal = True
            continue
        if t[0] == t[-1] == "`":
            inner = t[1:-1]
            in_query = "?" in "".join(literal_parts) or "?" in inner.split("${", 1)[0]

            def repl(m, _in_query=in_query):
                nonlocal param_counter
                param_counter += 1
                name = _sanitize_param_name(m.group(1), param_counter)
                if not _in_query:
                    path_params.append(name)
                return "{" + name + "}"

            literal_parts.append(_RE_TEMPLATE_VAR.sub(repl, inner))
            has_literal = True
            continue
        # Bare variable / expression segment inside concatenation. The
        # leading one is almost always a fixed base-URL prefix read from
        # config (this.baseUrl, environment.apiRootUrl, ...) — drop it
        # from the path instead of turning it into a bogus path param.
        if idx == 0 and len(tokens) > 1:
            base_expr = t
            continue
        param_counter += 1
        name = _sanitize_param_name(t, param_counter)
        # A bare variable appearing AFTER a literal '?' seen so far is
        # query data (its name is captured by the "key=" query-string
        # parser below), not a path segment — don't double-count it as
        # a path param too.
        if "?" not in "".join(literal_parts):
            path_params.append(name)
        literal_parts.append("{" + name + "}")

    full = "".join(literal_parts)
    resolvable = has_literal
    if not full:
        # Nothing but a single bare identifier/expression (no concat, no
        # literal anywhere) — not a usable path at all.
        full = "{" + _sanitize_param_name(url_expr.strip(), 1) + "}"
    # A valid OpenAPI/URL path always starts with "/" (or is a full
    # "http(s)://" URL) — including when `full` is ENTIRELY a param
    # placeholder like "{endpoint}" (no literal prefix at all), which
    # otherwise produces an invalid bare "{endpoint}" path key.
    if not full.startswith("/") and not full.startswith("http"):
        full = "/" + full

    path_part, _, query_part = full.partition("?")
    query: dict[str, str] = {}
    if query_part:
        for pair in query_part.split("&"):
            if not pair:
                continue
            k, _, v = pair.partition("=")
            query[k] = v if v else f"<{k}>"

    host = None
    is_absolute = bool(re.match(r"^https?://", path_part))
    if is_absolute:
        m = re.match(r"^(https?)://([^/]+)(/.*)?$", path_part)
        if m:
            host = m.group(2)
            path_part = m.group(3) or "/"

    return {
        "path_template": path_part if path_part else "/",
        "path_params": path_params,
        "query": query,
        "base_expr": base_expr,
        "resolvable": resolvable,
        "host": host,
    }


# ---------------------------------------------------------------------------
# Minimal, dependency-free YAML emitter (OpenAPI output needs no 3rd-party
# package, in keeping with js_deobfuscator.py's stdlib-only policy).
#
# Strategy: every scalar string is emitted JSON-double-quoted.  YAML's
# double-quoted scalar escaping is a superset of JSON's for every
# character this script ever produces, so json.dumps(value) is always a
# valid YAML double-quoted scalar — trading idiomatic unquoted-when-
# possible YAML for a much simpler, always-correct emitter. Verified by
# round-tripping sample documents through PyYAML during development.
# ---------------------------------------------------------------------------

_YAML_BOOL_OR_NULL_LIKE = {
    "true", "false", "null", "~", "yes", "no", "on", "off",
    "True", "False", "Null", "Yes", "No", "On", "Off",
    "TRUE", "FALSE", "NULL", "YES", "NO", "ON", "OFF",
}


def _yaml_scalar(value) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def _yaml_needs_quote(key: str) -> bool:
    if key == "":
        return True
    # A key that LOOKS like a number/bool/null would otherwise be parsed
    # back as that type instead of a string (e.g. OpenAPI's "200" status
    # code key, which MUST stay a string per the spec) — quote it.
    if key.isdigit():
        return True
    try:
        float(key)
        return True
    except ValueError:
        pass
    if key in _YAML_BOOL_OR_NULL_LIKE:
        return True
    if not all(c.isalnum() or c in "_-./" for c in key):
        return True
    if key[0] in "-?:,[]{}#&*!|>'\"%@`":
        return True
    return False


def _yaml_key_str(key) -> str:
    key_s = str(key)
    return _yaml_scalar(key_s) if _yaml_needs_quote(key_s) else key_s


def _yaml_render(obj, indent: int) -> list[str]:
    pad = "  " * indent
    lines: list[str] = []

    if isinstance(obj, dict):
        if not obj:
            lines.append(f"{pad}{{}}")
            return lines
        for key, value in obj.items():
            key_str = _yaml_key_str(key)
            if isinstance(value, dict) and value:
                lines.append(f"{pad}{key_str}:")
                lines.extend(_yaml_render(value, indent + 1))
            elif isinstance(value, list) and value:
                lines.append(f"{pad}{key_str}:")
                lines.extend(_yaml_render(value, indent))
            elif isinstance(value, dict):
                lines.append(f"{pad}{key_str}: {{}}")
            elif isinstance(value, list):
                lines.append(f"{pad}{key_str}: []")
            else:
                lines.append(f"{pad}{key_str}: {_yaml_scalar(value)}")
        return lines

    if isinstance(obj, list):
        if not obj:
            lines.append(f"{pad}[]")
            return lines
        for item in obj:
            if isinstance(item, (dict, list)) and item:
                item_lines = _yaml_render(item, indent + 1)
                first, *rest = item_lines
                # first currently has `pad + "  "` leading spaces; replace
                # the last two of those with "- " so it lines up under pad.
                lines.append(pad + "- " + first[len(pad) + 2 :])
                lines.extend(rest)
            else:
                lines.append(f"{pad}- {_yaml_scalar(item)}")
        return lines

    lines.append(pad + _yaml_scalar(obj))
    return lines


def yaml_dump(obj) -> str:
    return "\n".join(_yaml_render(obj, 0)) + "\n"


# ---------------------------------------------------------------------------
# OpenAPI 3.0 / Postman Collection v2.1 builders.
# ---------------------------------------------------------------------------

_SAFE_OPID = re.compile(r"[^a-zA-Z0-9_]+")
_RE_PATH_PARAM = re.compile(r"\{([A-Za-z_$][A-Za-z0-9_$]*)\}")


def _operation_id(method: str, path_template: str, seen: set[str]) -> str:
    base = method.lower() + "_" + _SAFE_OPID.sub("_", path_template.strip("/")).strip("_")
    base = base or method.lower() + "_root"
    opid = base
    n = 2
    while opid in seen:
        opid = f"{base}_{n}"
        n += 1
    seen.add(opid)
    return opid


def _json_schema_type(value) -> str:
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if value is None:
        return "string"
    return "object"


def build_openapi(calls: list[ApiCall], title: str, server_url: str | None) -> dict:
    """Builds an OpenAPI 3.0.3 document. Every call becomes one operation
    under its path_template; calls sharing a (method, path_template) pair
    across different files are each still recorded (only the LAST one
    wins in the paths dict, same as any dict — operations don't merge).
    Every operation carries an 'x-source' extension pointing back at the
    exact file:line it was reconstructed from, since the generated
    paths/examples are a static best-effort guess, not a verified
    contract — x-source is what lets a reviewer go check the original
    source."""
    paths: dict[str, dict] = {}
    seen_opids: set[str] = set()
    external_servers: set[str] = set()

    for call in calls:
        info = analyze_url(call.url)
        path_template = info["path_template"]

        if info["host"]:
            external_servers.add(f"https://{info['host']}")

        method_lower = call.method.lower()
        if method_lower not in HTTP_VERBS:
            method_lower = "post"

        path_entry = paths.setdefault(path_template, {})
        op: dict = {
            "operationId": _operation_id(method_lower, path_template, seen_opids),
            "summary": f"{call.client} call found in {call.file}:{call.line}",
            "x-source": {"file": call.file, "line": call.line, "client": call.client},
            "responses": {"200": {"description": "OK"}},
        }

        parameters = []
        for p in info["path_params"]:
            parameters.append(
                {"name": p, "in": "path", "required": True, "schema": {"type": "string"}}
            )
        for qname, qexample in info["query"].items():
            parameters.append(
                {
                    "name": qname,
                    "in": "query",
                    "required": False,
                    "schema": {"type": "string"},
                    "example": qexample,
                }
            )
        if parameters:
            op["parameters"] = parameters

        if not info["resolvable"]:
            op["x-source"]["x-unresolved-url"] = call.url

        body_example = body_expr_to_example(call.body)
        if body_example is not None:
            # schema.type must match the example's actual JSON type — an
            # unresolved body expression (bare variable, function call)
            # becomes a "<expr>" placeholder STRING, not an object, and
            # declaring "object" while the example is a string fails
            # schema validation (confirmed with `redocly lint`).
            op["requestBody"] = {
                "content": {
                    "application/json": {
                        "schema": {"type": _json_schema_type(body_example)},
                        "example": body_example,
                    }
                }
            }

        path_entry[method_lower] = op

    openapi: dict = {
        "openapi": "3.0.3",
        "info": {"title": title, "version": "1.0.0"},
        "paths": paths,
    }
    servers = []
    if server_url:
        servers.append({"url": server_url})
    for ext in sorted(external_servers):
        servers.append({"url": ext})
    if servers:
        openapi["servers"] = servers
    return openapi


def _postman_body(body_example) -> dict | None:
    if body_example is None:
        return None
    return {
        "mode": "raw",
        "raw": json.dumps(body_example, indent=2, ensure_ascii=False),
        "options": {"raw": {"language": "json"}},
    }


def _postman_url(path_template: str, host: str | None, base_url_var: str, query: dict) -> dict:
    """Builds a Postman url object from an ALREADY host-stripped
    path_template (analyze_url puts the host, if any, in its own 'host'
    field — this function never re-splits a full URL). Postman's own
    path-variable syntax is ':name' (not OpenAPI's '{name}'), and
    unresolved path segments need a matching entry in url.variable for
    the Postman UI to treat them as editable variables rather than
    literal text — so '{id}' segments are rewritten to ':id' in both
    url.path and url.raw, with one url.variable entry per path param."""
    segments = [s for s in path_template.split("/") if s != ""]
    pm_segments: list[str] = []
    variables: list[dict] = []
    for seg in segments:
        m = _RE_PATH_PARAM.fullmatch(seg)
        if m:
            name = m.group(1)
            pm_segments.append(":" + name)
            variables.append({"key": name, "value": ""})
        else:
            pm_segments.append(seg)

    if host:
        raw_prefix = f"https://{host}"
        host_list = host.split(".")
    else:
        raw_prefix = "{{" + base_url_var + "}}"
        host_list = ["{{" + base_url_var + "}}"]

    raw = raw_prefix + "/" + "/".join(pm_segments) if pm_segments else raw_prefix
    if query:
        raw += "?" + "&".join(f"{k}={v}" for k, v in query.items())

    url: dict = {"raw": raw, "host": host_list}
    if pm_segments:
        url["path"] = pm_segments
    if query:
        url["query"] = [{"key": k, "value": str(v)} for k, v in query.items()]
    if variables:
        url["variable"] = variables
    return url


def build_postman_collection(
    calls: list[ApiCall], collection_name: str, base_url_var: str, server_url: str | None
) -> dict:
    items = []
    for call in calls:
        info = analyze_url(call.url)
        path_template = info["path_template"]

        url = _postman_url(path_template, info["host"], base_url_var, info["query"])

        item: dict = {
            "name": f"{call.method} {path_template}",
            "request": {
                "method": call.method,
                "header": [{"key": "Content-Type", "value": "application/json"}],
                "url": url,
                "description": f"Reconstructed from {call.file}:{call.line} ({call.client})",
            },
            "response": [],
        }

        body_example = body_expr_to_example(call.body)
        body = _postman_body(body_example)
        if body:
            item["request"]["body"] = body

        items.append(item)

    collection: dict = {
        "info": {
            "name": collection_name,
            "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
        },
        "item": items,
    }
    if not server_url:
        server_url = ""
    collection["variable"] = [{"key": base_url_var, "value": server_url}]
    return collection


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Reconstructs API calls (method/url/body) found in one or more JavaScript files."
    )
    parser.add_argument("arquivos", type=Path, nargs="+", help="Caminho(s) de arquivo(s) .js a analisar")
    parser.add_argument("--relatorio-json", type=Path, help="Caminho para salvar o relatorio em JSON")
    parser.add_argument("--openapi", type=Path, help="Caminho para salvar a especificacao OpenAPI 3.0 (YAML)")
    parser.add_argument("--postman", type=Path, help="Caminho para salvar a collection do Postman (JSON v2.1)")
    parser.add_argument("--title", default="Reconstructed API", help="Titulo da API / nome da collection")
    parser.add_argument(
        "--server-url", default=None, help="URL base da API (OpenAPI servers[0].url / Postman {{baseUrl}})"
    )
    parser.add_argument(
        "--base-url-var", default="baseUrl", help="Nome da variavel Postman para a URL base (default: baseUrl)"
    )
    args = parser.parse_args()

    missing = [str(p) for p in args.arquivos if not p.exists()]
    if missing:
        print(f"Erro: arquivo(s) nao encontrado(s): {', '.join(missing)}", file=sys.stderr)
        sys.exit(1)

    calls = process_files(args.arquivos)

    imprimir_relatorio_humano(calls)

    if args.relatorio_json:
        args.relatorio_json.write_text(
            json.dumps([c.to_dict() for c in calls], indent=2, ensure_ascii=False),
            encoding="utf-8",
        )

    if args.openapi:
        openapi = build_openapi(calls, args.title, args.server_url)
        args.openapi.write_text(yaml_dump(openapi), encoding="utf-8")

    if args.postman:
        collection = build_postman_collection(calls, args.title, args.base_url_var, args.server_url)
        args.postman.write_text(
            json.dumps(collection, indent=2, ensure_ascii=False), encoding="utf-8"
        )


if __name__ == "__main__":
    main()
