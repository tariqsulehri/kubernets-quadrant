#!/bin/bash

set -euo pipefail

NAMESPACE=${NAMESPACE:-qdrant}
RELEASE_NAME=${RELEASE_NAME:-qdrant}
SERVICE_NAME=${SERVICE_NAME:-qdrant}
COLLECTION=${COLLECTION:-}
EXPECTED_REPLICAS=${EXPECTED_REPLICAS:-3}
MIN_DISTINCT_NODES=${MIN_DISTINCT_NODES:-3}
LOCAL_PORT=${LOCAL_PORT:-6333}
QDRANT_URL=${QDRANT_URL:-}
PORT_FORWARD_PID=""

log() {
  printf '[INFO] %s\n' "$*"
}

pass() {
  printf '[PASS] %s\n' "$*"
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]]; then
    kill "${PORT_FORWARD_PID}" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Required tool not found: $1"
}

require_tool kubectl
require_tool curl
require_tool python3

get_url() {
  if [[ -n "${QDRANT_URL}" ]]; then
    printf '%s' "${QDRANT_URL%/}"
    return 0
  fi

  kubectl port-forward -n "${NAMESPACE}" "svc/${SERVICE_NAME}" "${LOCAL_PORT}:6333" >/tmp/qdrant-ha-port-forward.log 2>&1 &
  PORT_FORWARD_PID=$!

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${LOCAL_PORT}/readyz" >/dev/null 2>&1; then
      printf 'http://127.0.0.1:%s' "${LOCAL_PORT}"
      return 0
    fi
    sleep 1
  done

  fail "Timed out waiting for Qdrant port-forward. See /tmp/qdrant-ha-port-forward.log"
}

validate_statefulset() {
  local replicas ready

  replicas=$(kubectl get statefulset "${RELEASE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
  ready=$(kubectl get statefulset "${RELEASE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.readyReplicas}')
  ready=${ready:-0}

  [[ "${replicas}" == "${EXPECTED_REPLICAS}" ]] || fail "Expected StatefulSet replicas=${EXPECTED_REPLICAS}, found ${replicas}"
  [[ "${ready}" == "${EXPECTED_REPLICAS}" ]] || fail "Expected readyReplicas=${EXPECTED_REPLICAS}, found ${ready}"

  pass "StatefulSet ${RELEASE_NAME} is ready with ${ready}/${replicas} replicas"
}

validate_pods() {
  local pod_lines pod_count=0 distinct_nodes

  pod_lines=$(kubectl get pods -n "${NAMESPACE}" \
    -l "app.kubernetes.io/instance=${RELEASE_NAME},app.kubernetes.io/name=qdrant" \
    -o jsonpath='{range .items[*]}{.metadata.name}{";"}{.status.phase}{";"}{range .status.containerStatuses[*]}{.ready}{" "}{end}{";"}{.spec.nodeName}{"\n"}{end}')

  [[ -n "${pod_lines}" ]] || fail "No Qdrant pods found for release ${RELEASE_NAME}"

  while IFS=';' read -r pod_name phase readiness node_name; do
    [[ -n "${pod_name}" ]] || continue
    pod_count=$((pod_count + 1))

    [[ "${phase}" == "Running" ]] || fail "Pod ${pod_name} phase is ${phase}, expected Running"
    [[ "${readiness}" != *false* ]] || fail "Pod ${pod_name} has an unready container"
    [[ -n "${node_name}" ]] || fail "Pod ${pod_name} is not assigned to a node"
  done <<< "${pod_lines}"

  [[ "${pod_count}" -eq "${EXPECTED_REPLICAS}" ]] || fail "Expected ${EXPECTED_REPLICAS} Qdrant pods, found ${pod_count}"

  distinct_nodes=$(printf '%s\n' "${pod_lines}" | awk -F';' 'NF >= 4 && $4 != "" {print $4}' | sort -u | wc -l | tr -d ' ')
  [[ "${distinct_nodes}" -ge "${MIN_DISTINCT_NODES}" ]] || fail "Expected at least ${MIN_DISTINCT_NODES} distinct nodes, found ${distinct_nodes}"

  pass "Qdrant pods are running and distributed across ${distinct_nodes} node(s)"
}

validate_pvcs() {
  local pvc_lines

  pvc_lines=$(kubectl get pvc -n "${NAMESPACE}" -o jsonpath='{range .items[*]}{.metadata.name}{";"}{.status.phase}{"\n"}{end}' | grep '^qdrant-' || true)
  [[ -n "${pvc_lines}" ]] || fail "No Qdrant PVCs found in namespace ${NAMESPACE}"

  while IFS=';' read -r pvc_name phase; do
    [[ -n "${pvc_name}" ]] || continue
    [[ "${phase}" == "Bound" ]] || fail "PVC ${pvc_name} phase is ${phase}, expected Bound"
  done <<< "${pvc_lines}"

  pass "All Qdrant PVCs are Bound"
}

validate_pdb() {
  local max_unavailable

  max_unavailable=$(kubectl get pdb "${RELEASE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.maxUnavailable}' 2>/dev/null || true)
  [[ -n "${max_unavailable}" ]] || fail "PodDisruptionBudget ${RELEASE_NAME} not found"

  pass "PodDisruptionBudget ${RELEASE_NAME} is present with maxUnavailable=${max_unavailable}"
}

validate_api() {
  local base_url ready_response cluster_response peer_count
  base_url=$(get_url)

  ready_response=$(curl -fsS "${base_url}/readyz")
  [[ "${ready_response}" == *ready* ]] || fail "Unexpected readiness response: ${ready_response}"
  pass "Qdrant readiness endpoint returned a healthy response"

  cluster_response=$(curl -fsS "${base_url}/cluster")
  [[ "${cluster_response}" != *"Distributed mode disabled"* ]] || fail "Distributed mode is not enabled for this cluster"

  peer_count=$(CLUSTER_RESPONSE="${cluster_response}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["CLUSTER_RESPONSE"])
result = payload.get("result", payload)
peers = result.get("peers", {})

if isinstance(peers, dict):
    print(len(peers))
elif isinstance(peers, list):
    print(len(peers))
else:
    print(0)
PY
)

  [[ "${peer_count}" -ge "${EXPECTED_REPLICAS}" ]] || fail "Expected at least ${EXPECTED_REPLICAS} cluster peers, found ${peer_count}"
  pass "Cluster API reports ${peer_count} peer(s)"

  if [[ -n "${COLLECTION}" ]]; then
    local collection_response collection_cluster points_count
    collection_response=$(curl -fsS "${base_url}/collections/${COLLECTION}")
    points_count=$(COLLECTION_RESPONSE="${collection_response}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["COLLECTION_RESPONSE"])
result = payload.get("result", payload)
print(result.get("points_count", 0))
PY
)

    collection_cluster=$(curl -fsS "${base_url}/collections/${COLLECTION}/cluster")
    [[ -n "${collection_cluster}" ]] || fail "Collection cluster response is empty for ${COLLECTION}"
    pass "Collection ${COLLECTION} is reachable with points_count=${points_count}"
  fi
}

main() {
  log "Validating HA deployment for release ${RELEASE_NAME} in namespace ${NAMESPACE}"
  validate_statefulset
  validate_pods
  validate_pvcs
  validate_pdb
  validate_api
  pass "HA validation completed successfully"
}

main "$@"
