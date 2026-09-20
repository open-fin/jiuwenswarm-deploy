#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 <rendered-agentserver.json> <output.json> [restricted|privileged]" >&2
}

[[ $# -ge 2 && $# -le 3 ]] || { usage; exit 2; }

source_json=$1
output_json=$2
mode=${3:-restricted}

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -f "$source_json" ]] || { echo "Input does not exist: $source_json" >&2; exit 1; }
[[ "$source_json" != "$output_json" ]] || { echo "Input and output must differ" >&2; exit 1; }
[[ "$mode" == "restricted" || "$mode" == "privileged" ]] || { usage; exit 2; }

output_parent=$(dirname "$output_json")
mkdir -p "$output_parent"
[[ ! -e "$output_json" ]] || { echo "Refusing to overwrite: $output_json" >&2; exit 1; }

if [[ "$mode" == "restricted" ]]; then
    jq '
      .rawdata.containers |= map(select(.container_id != "c-jiuwenbox"))
      | .rawdata.containers |= map(
          if .container_id == "c-agentserver" then
            .securityContext = {
              "runAsNonRoot": true,
              "allowPrivilegeEscalation": false,
              "capabilities": {"drop": ["ALL"]},
              "seccompProfile": {"type": "RuntimeDefault"}
            }
          else . end
        )
      | .rawdata.templates |= map(
          del(.fsGroup, .nodeName)
          | .sidecar_container_ids |= map(select(. != "c-jiuwenbox"))
          | .volumes |= map(select(.name != "hp-cgroup"))
        )
      | (.rawdata.templates | map(.volumes | map(.name)) | add | unique) as $keep
      | .rawdata.containers |= map(
          if has("volumeMounts") then
            .volumeMounts |= map(select(.name as $name | $keep | index($name)))
          else . end
        )
    ' "$source_json" > "$output_json"
else
    # 只让 AgentServer 主容器使用随机 UID。JiuwenBox 原有 root、capability、
    # unconfined seccomp/AppArmor 与 cgroup hostPath 保持不变，必须由专用 SCC 审批。
    jq '
      .rawdata.containers |= map(
          if .container_id == "c-agentserver" then
            .securityContext = {
              "runAsNonRoot": true,
              "allowPrivilegeEscalation": false,
              "capabilities": {"drop": ["ALL"]},
              "seccompProfile": {"type": "RuntimeDefault"}
            }
          else . end
        )
      | .rawdata.templates |= map(del(.fsGroup, .nodeName))
    ' "$source_json" > "$output_json"
fi

jq -e '
  .type == "config_sync"
  and (.rawdata.containers | type == "array")
  and (.rawdata.templates | type == "array")
' "$output_json" >/dev/null

echo "Wrote $output_json (JIUWENBOX_MODE=$mode)"
