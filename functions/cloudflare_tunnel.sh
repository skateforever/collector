#!/bin/bash
#############################################################
#                                                           #
# Cloudflare quick-tunnel for the app-report dashboard.     #
# Opt-in via cloudflare_tunnel="yes" in collector.cfg; only #
# meaningful when app-report is up (background mode). The   #
# tunnel gives the local gunicorn an ephemeral              #
# https://*.trycloudflare.com URL so the dashboard is       #
# reachable without exposing the VPS IP/port directly.      #
#                                                           #
# Exposes:                                                  #
#   * start_cloudflare_tunnel                               #
#                                                           #
#############################################################

# Launch a cloudflared quick-tunnel pointing at the local app-report
# port. Same PID-file discipline as start_app_report so concurrent recon
# runs share a single tunnel. The trycloudflare URL is parsed back out of
# cloudflared's log and echoed for the operator. Failure is non-fatal:
# the run finishes whether or not the tunnel comes up — the local
# gunicorn is still serving.
start_cloudflare_tunnel(){
    local local_port="$1"
    local cf_pidfile="${cloudflare_tunnel_pidfile:-${output_dir}/${cloudflare_tunnel_pidfile_name:-.cloudflared.pid}}"
    local cf_logfile="${cloudflare_tunnel_logfile:-${output_dir}/${cloudflare_tunnel_logfile_name:-.cloudflared.log}}"
    local cf_timeout="${cloudflare_tunnel_url_timeout:-30}"

    if ! command -v cloudflared >/dev/null 2>&1; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: cloudflared binary not found in PATH, skipping (install it or set cloudflare_tunnel=\"no\")."
        return 0
    fi

    # Already running? Trust the PID file iff the process is alive. We
    # also try to recover the public URL from the existing logfile so the
    # operator sees it again on every run instead of having to grep.
    if [[ -s "${cf_pidfile}" ]]; then
        local cf_existing
        cf_existing="$(cat "${cf_pidfile}" 2>/dev/null)"
        if [[ -n "${cf_existing}" ]] && kill -0 "${cf_existing}" 2>/dev/null; then
            local cf_url_existing
            cf_url_existing="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${cf_logfile}" 2>/dev/null | tail -n1)"
            if [[ -n "${cf_url_existing}" ]]; then
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: already running (pid ${cf_existing}) → ${cf_url_existing}"
            else
                echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: already running (pid ${cf_existing}, log ${cf_logfile})"
            fi
            return 0
        fi
        rm -f "${cf_pidfile}"
    fi

    # Truncate the logfile so the URL we grep for below is from THIS
    # tunnel run, not a previous one.
    : > "${cf_logfile}"

    (
        nohup cloudflared tunnel --no-autoupdate --url "http://localhost:${local_port}" \
            >> "${cf_logfile}" 2>&1 &
        echo $! > "${cf_pidfile}"
    )

    # Give cloudflared up to ${cf_timeout} seconds to print the
    # trycloudflare URL. The URL appears in stderr (which we redirected
    # into the logfile) within a couple of seconds in practice, so 30s is
    # generous.
    local cf_url=""
    local waited=0
    while [[ "${waited}" -lt "${cf_timeout}" ]]; do
        if [[ -s "${cf_pidfile}" ]] && ! kill -0 "$(cat "${cf_pidfile}")" 2>/dev/null; then
            echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: cloudflared exited before publishing a URL (see ${cf_logfile})"
            rm -f "${cf_pidfile}"
            return 1
        fi
        cf_url="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "${cf_logfile}" 2>/dev/null | tail -n1)"
        [[ -n "${cf_url}" ]] && break
        sleep 1
        waited=$((waited + 1))
    done

    if [[ -n "${cf_url}" ]]; then
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: serving at ${cf_url} (pid $(cat "${cf_pidfile}"), log ${cf_logfile})"
    else
        echo -e "${yellow}$(date +"%d/%m/%Y %H:%M")${reset} ${red}>>${reset} start_cloudflare_tunnel: timed out waiting for trycloudflare URL after ${cf_timeout}s (see ${cf_logfile}); tunnel may still be starting."
    fi
}
