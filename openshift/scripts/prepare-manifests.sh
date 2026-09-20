#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: prepare-manifests.sh <jiuwenswarm-conf-dir> <empty-output-dir> <profile-env>

The input directory must be produced by JiuwenSwarm dev-stable deploy/enterprise
with --render-only. The output directory must be empty or absent.
EOF
}

[[ $# -eq 3 ]] || { usage; exit 2; }

source_dir=$1
output_dir=$2
profile_file=$3
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
profile_dir=$(cd "$script_dir/.." && pwd)

command -v yq >/dev/null 2>&1 || { echo "mikefarah/yq v4 is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[[ -d "$source_dir" ]] || { echo "Input directory does not exist: $source_dir" >&2; exit 1; }
[[ -f "$profile_file" ]] || { echo "Profile file does not exist: $profile_file" >&2; exit 1; }

mkdir -p "$output_dir"
if find "$output_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    echo "Output directory must be empty: $output_dir" >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "$profile_file"
set +a

required_vars=(NAMESPACE ROUTE_NAME ROUTE_HOST WEB_SERVICE WEB_SERVICE_PORT)
for name in "${required_vars[@]}"; do
    [[ -n "${!name:-}" ]] || { echo "Missing $name in $profile_file" >&2; exit 1; }
done

TLS_TERMINATION=${TLS_TERMINATION:-edge}
INSECURE_EDGE_POLICY=${INSECURE_EDGE_POLICY:-Redirect}
ROUTE_TIMEOUT=${ROUTE_TIMEOUT:-1h}
ROUTE_TUNNEL_TIMEOUT=${ROUTE_TUNNEL_TIMEOUT:-1h}
JIUWENBOX_MODE=${JIUWENBOX_MODE:-restricted}

[[ "$TLS_TERMINATION" == "edge" ]] || {
    echo "Only edge TLS is supported by the current HTTP-only Web image" >&2
    exit 1
}

# Copy only JiuwenSwarm application artifacts. A conf directory can contain
# stale built-in NFS/DB/MinIO manifests from an earlier render; those must not
# become part of the OpenShift application profile accidentally.
application_files=(
    configmap-secret.yaml
    gateway-config.configmap.yaml
    gateway-env.configmap.yaml
    gateway.yaml
    manager-server.yaml
    identity.yaml
    manager-web.yaml
    agentserver-env.configmap.yaml
    runtime.yaml
    web.yaml
)

copied=0
for file_name in "${application_files[@]}"; do
    source_file="$source_dir/$file_name"
    [[ -f "$source_file" ]] || continue
    output_file="$output_dir/$(basename "$source_file")"
    if [[ "$file_name" == "manager-web.yaml" ]]; then
        # Manager Web has only a NodePort Service upstream. Keep it reachable
        # inside the cluster by converting that Service to ClusterIP.
        cp "$source_file" "$output_file"
        yq eval -i '
          (select(.kind == "Service" and .spec.type == "NodePort") | .spec.type) = "ClusterIP"
          | del(select(.kind == "Service").spec.ports[].nodePort)
        ' "$output_file"
    else
        yq eval-all 'select(.kind != "Service" or .spec.type != "NodePort")' \
            "$source_file" > "$output_file"
    fi

    # OpenShift restricted-v2 chooses a namespace-specific UID. Remove fixed IDs
    # and apply the restricted pod/container baseline to application Deployments.
    yq eval -i '
      (select(.kind == "Deployment") | .spec.template.spec.securityContext) |= (
          (. // {})
          | del(.fsGroup)
          | .seccompProfile.type = "RuntimeDefault"
        )
      | (select(.kind == "Deployment") | .spec.template.spec.containers[].securityContext) |= (
          (. // {})
          | del(.runAsUser, .runAsGroup, .appArmorProfile, .seccompProfile)
          | .runAsNonRoot = true
          | .allowPrivilegeEscalation = false
          | .capabilities = {"drop": ["ALL"]}
        )
    ' "$output_file"
    copied=$((copied + 1))
done

[[ $copied -gt 0 ]] || { echo "No JiuwenSwarm application manifests found in $source_dir" >&2; exit 1; }

cp "$profile_dir/route.template.yaml" "$output_dir/route.yaml"
NAMESPACE="$NAMESPACE" ROUTE_NAME="$ROUTE_NAME" ROUTE_HOST="$ROUTE_HOST" \
WEB_SERVICE="$WEB_SERVICE" WEB_SERVICE_PORT="$WEB_SERVICE_PORT" \
TLS_TERMINATION="$TLS_TERMINATION" INSECURE_EDGE_POLICY="$INSECURE_EDGE_POLICY" \
ROUTE_TIMEOUT="$ROUTE_TIMEOUT" ROUTE_TUNNEL_TIMEOUT="$ROUTE_TUNNEL_TIMEOUT" \
yq eval -i '
  .metadata.name = strenv(ROUTE_NAME)
  | .metadata.namespace = strenv(NAMESPACE)
  | .metadata.annotations."haproxy.router.openshift.io/timeout" = strenv(ROUTE_TIMEOUT)
  | .metadata.annotations."haproxy.router.openshift.io/timeout-tunnel" = strenv(ROUTE_TUNNEL_TIMEOUT)
  | .spec.host = strenv(ROUTE_HOST)
  | .spec.to.name = strenv(WEB_SERVICE)
  | .spec.port.targetPort = strenv(WEB_SERVICE_PORT)
  | .spec.tls.termination = strenv(TLS_TERMINATION)
  | .spec.tls.insecureEdgeTerminationPolicy = strenv(INSECURE_EDGE_POLICY)
' "$output_dir/route.yaml"

if [[ -f "$source_dir/agentserver.json" ]]; then
    "$script_dir/adapt-agentserver-template.sh" \
        "$source_dir/agentserver.json" \
        "$output_dir/agentserver.openshift.json" \
        "$JIUWENBOX_MODE"
else
    echo "WARNING: agentserver.json not found; Runtime cannot create an OpenShift-adapted AgentServer yet" >&2
fi

cat <<EOF
Prepared $copied manifest file(s) in $output_dir
Route: https://$ROUTE_HOST
Next: inspect the output, run oc apply --dry-run=server, then follow openshift/README.md.
EOF
