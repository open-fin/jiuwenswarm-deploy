#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <namespace> <agentserver.openshift.json> [runtime-service] [runtime-port] [local-port]" >&2
}

[[ $# -ge 2 && $# -le 5 ]] || { usage; exit 2; }

namespace=$1
template_file=$2
runtime_service=${3:-jiuwenclaw-agent-runtime}
runtime_port=${4:-8091}
local_port=${5:-18091}

command -v oc >/dev/null 2>&1 || { echo "oc is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "$template_file" ]] || { echo "Template does not exist: $template_file" >&2; exit 1; }
jq -e '.type == "config_sync"' "$template_file" >/dev/null

forward_log=$(mktemp)
response_file=$(mktemp)
port_forward_pid=""
cleanup() {
    [[ -z "$port_forward_pid" ]] || kill "$port_forward_pid" >/dev/null 2>&1 || true
    rm -f "$forward_log" "$response_file"
}
trap cleanup EXIT INT TERM

oc -n "$namespace" port-forward "service/$runtime_service" \
    "$local_port:$runtime_port" >"$forward_log" 2>&1 &
port_forward_pid=$!

ready=false
for _ in $(seq 1 30); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$local_port/healthz" >/dev/null; then
        ready=true
        break
    fi
    if ! kill -0 "$port_forward_pid" >/dev/null 2>&1; then
        cat "$forward_log" >&2
        exit 1
    fi
    sleep 1
done
[[ "$ready" == "true" ]] || { cat "$forward_log" >&2; echo "Runtime port-forward did not become ready" >&2; exit 1; }

http_code=$(curl -sS --max-time 30 -o "$response_file" -w '%{http_code}' \
    -X POST "http://127.0.0.1:$local_port/api/session/config_sync" \
    -H 'Content-Type: application/json' \
    --data-binary "@$template_file")

if [[ ! "$http_code" =~ ^2[0-9][0-9]$ ]] || ! jq -e '.ok == true' "$response_file" >/dev/null; then
    echo "config_sync failed: HTTP $http_code" >&2
    cat "$response_file" >&2
    exit 1
fi

echo "AgentServer OpenShift template accepted by Runtime"
