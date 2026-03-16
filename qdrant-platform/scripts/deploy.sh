#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLATFORM_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
NAMESPACE=${NAMESPACE:-qdrant}
RELEASE_NAME=${RELEASE_NAME:-qdrant}
DEPLOY_PROFILE=${DEPLOY_PROFILE:-prod}
HELM_VALUES_FILE=${HELM_VALUES_FILE:-}

if [[ -z "${HELM_VALUES_FILE}" ]]; then
  case "${DEPLOY_PROFILE}" in
    prod)
      HELM_VALUES_FILE="${PLATFORM_ROOT}/helm/qdrant/values-prod.yaml"
      ;;
    local)
      HELM_VALUES_FILE="${PLATFORM_ROOT}/helm/qdrant/values-local.yaml"
      ;;
    staging)
      HELM_VALUES_FILE="${PLATFORM_ROOT}/helm/qdrant/values-staging.yaml"
      ;;
    dev)
      HELM_VALUES_FILE="${PLATFORM_ROOT}/helm/qdrant/values-dev.yaml"
      ;;
    *)
      echo "Unsupported DEPLOY_PROFILE: ${DEPLOY_PROFILE}" >&2
      exit 1
      ;;
  esac
fi

# ── Step 1: RBAC fix for multi-node Minikube storage provisioner ──────────────
# The Minikube storage provisioner lacks permission to read node info in
# multi-node clusters. Without this, PVCs using WaitForFirstConsumer binding
# stay Pending indefinitely. This ClusterRole grants the missing node read access.
echo "Step 1: Applying storage provisioner RBAC..."
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/rbac/storage-provisioner-rbac.yaml"

# ── Step 2: Storage classes ───────────────────────────────────────────────────
# Creates qdrant-fast-ssd (live vector data) and qdrant-snapshots (backup
# storage) storage classes. Both use the Minikube hostpath provisioner with
# WaitForFirstConsumer so volumes are placed on the same node as their pod.
echo "Step 2: Applying storage classes..."
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/storage/storage-class.yaml"

# ── Step 3: Node zone labels ──────────────────────────────────────────────────
# The prod values file enforces a topology spread constraint with
# DoNotSchedule across availability zones. Kubernetes will refuse to schedule
# pods if zone labels are missing. This script assigns zone-a, zone-b, zone-c
# round-robin across all available nodes.
echo "Step 3: Labeling nodes with zone topology..."
bash "${PLATFORM_ROOT}/scripts/label-nodes.sh"

# ── Step 4: Namespace ─────────────────────────────────────────────────────────
# Creates the qdrant namespace if it does not already exist. The dry-run pipe
# pattern makes this safe to run on an existing cluster without error.
echo "Step 4: Creating namespace ${NAMESPACE}..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── Step 5: Wipe stale Raft state from any previous deployment ───────────────
# Qdrant persists Raft peer IDs in THREE places that must all be cleared:
#
#   1. In the live cluster Raft log — the leader keeps committed peer IDs in
#      memory. A new pod with a fresh peer ID will be rejected by the leader
#      with "Failed to add peer" causing CrashLoopBackOff on qdrant-2.
#
#   2. On the PVC — raft_state.json is written to /qdrant/storage/ inside
#      each pod's PersistentVolume.
#
#   3. On the Minikube host filesystem — the hostpath provisioner stores PVC
#      data under /tmp/hostpath-provisioner and /var/hostpath-provisioner on
#      each node. When a PVC is deleted and recreated, the provisioner reuses
#      the same host directory, so raft_state.json survives PVC recreation.
#      This is the root cause of persistent CrashLoopBackOff across redeployments.
#
# Cleanup sequence:
#   1. Remove all peers from the live cluster API (clears in-memory Raft log)
#   2. Force-delete all pods (releases PVC holds)
#   3. Patch finalizers and delete all PVCs (removes Kubernetes objects)
#   4. Wipe hostpath directories on all Minikube nodes (removes data from disk)

echo "Step 5: Checking for existing Qdrant deployment to clean up..."

QDRANT_LOCAL_PORT=16333
PF_PID=""

# Always attempt peer cleanup if any running pod exists
QDRANT_POD=$(kubectl get pods -n "${NAMESPACE}" \
  -l "app.kubernetes.io/name=qdrant,app.kubernetes.io/instance=${RELEASE_NAME}" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

if [[ -n "${QDRANT_POD}" ]]; then
  echo "Step 5: Found running pod ${QDRANT_POD} — cleaning up Raft peer state..."
  kubectl port-forward -n "${NAMESPACE}" "pod/${QDRANT_POD}" "${QDRANT_LOCAL_PORT}:6333" &>/dev/null &
  PF_PID=$!
  sleep 3

  CLUSTER_JSON=$(curl -sf "http://127.0.0.1:${QDRANT_LOCAL_PORT}/cluster" 2>/dev/null || true)

  if [[ -n "${CLUSTER_JSON}" ]]; then
    LEADER_ID=$(echo "${CLUSTER_JSON}" | python3 -c \
      "import sys,json; d=json.load(sys.stdin)['result']; print(d['raft_info']['leader'])" 2>/dev/null || true)

    ALL_PEER_IDS=$(echo "${CLUSTER_JSON}" | python3 -c \
      "import sys,json; [print(k) for k in json.load(sys.stdin)['result']['peers'].keys()]" 2>/dev/null || true)

    # Remove non-leader peers first to avoid disrupting the leader prematurely
    for PEER_ID in ${ALL_PEER_IDS}; do
      if [[ "${PEER_ID}" != "${LEADER_ID}" ]]; then
        echo "Step 5: Removing peer ${PEER_ID}..."
        curl -sf -X DELETE \
          "http://127.0.0.1:${QDRANT_LOCAL_PORT}/cluster/peer/${PEER_ID}?force=true" \
          >/dev/null 2>&1 || true
      fi
    done

    # Remove leader last
    if [[ -n "${LEADER_ID}" ]]; then
      echo "Step 5: Removing leader peer ${LEADER_ID}..."
      curl -sf -X DELETE \
        "http://127.0.0.1:${QDRANT_LOCAL_PORT}/cluster/peer/${LEADER_ID}?force=true" \
        >/dev/null 2>&1 || true
    fi

    echo "Step 5: All peers removed from Raft log."
  else
    echo "Step 5: Could not reach cluster API — skipping peer removal."
  fi

  kill "${PF_PID}" 2>/dev/null || true
  wait "${PF_PID}" 2>/dev/null || true
else
  echo "Step 5: No running Qdrant pod found — skipping peer API cleanup."
fi

# Force-delete all pods to release PVC holds
echo "Step 5: Force deleting all pods..."
kubectl delete pod -n "${NAMESPACE}" --all --grace-period=0 --force \
  --ignore-not-found 2>/dev/null || true
sleep 3

# Patch finalizers off any stuck PVCs then delete
existing_pvcs=$(kubectl get pvc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "${existing_pvcs}" -gt 0 ]]; then
  echo "Step 5: Removing PVC finalizers and deleting ${existing_pvcs} PVC(s)..."
  for PVC in $(kubectl get pvc -n "${NAMESPACE}" --no-headers \
               -o custom-columns=":metadata.name" 2>/dev/null); do
    kubectl patch pvc "${PVC}" -n "${NAMESPACE}" \
      -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl delete pvc "${PVC}" -n "${NAMESPACE}" \
      --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  done

  # Wait until all PVCs are fully gone before wiping hostpath
  echo "Step 5: Waiting for all PVCs to terminate..."
  for i in $(seq 1 30); do
    remaining=$(kubectl get pvc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "${remaining}" -eq 0 ]]; then
      echo "Step 5: All PVCs cleared."
      break
    fi
    echo "Step 5: Waiting... (${remaining} PVC(s) still terminating)"
    sleep 3
  done
else
  echo "Step 5: No PVCs found — skipping PVC wipe."
fi

# Wipe hostpath directories on all Minikube nodes.
# The Minikube hostpath provisioner reuses host directories when PVCs are
# recreated, so raft_state.json survives PVC deletion unless the underlying
# host directory is explicitly removed. This must run after PVCs are gone.
echo "Step 5: Wiping hostpath storage directories on all Minikube nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  echo "Step 5: Cleaning node ${node}..."
  minikube ssh -n "${node}" -- \
    "sudo rm -rf /tmp/hostpath-provisioner/${NAMESPACE}/ /var/hostpath-provisioner/${NAMESPACE}/ 2>/dev/null || true"
done
echo "Step 5: Hostpath directories cleared."

# ── Step 6: Helm deployment ───────────────────────────────────────────────────
# Deploys the Qdrant StatefulSet, Services, Ingress, PodDisruptionBudget, and
# ServiceAccount using the selected environment values file. The --install flag
# ensures a clean install if no release exists; upgrade handles subsequent runs.
echo "Step 6: Deploying ${RELEASE_NAME} into namespace ${NAMESPACE} using ${HELM_VALUES_FILE}..."
helm upgrade --install "${RELEASE_NAME}" qdrant/qdrant \
  -n "${NAMESPACE}" \
  -f "${HELM_VALUES_FILE}"

# ── Step 7: Network policies ──────────────────────────────────────────────────
# Applies NetworkPolicy rules restricting ingress and egress to qdrant pods,
# preventing unauthorized lateral movement within the cluster. Rules explicitly
# allow inter-pod p2p traffic on port 6335 for Raft consensus, gRPC on 6334
# for shard replication, DNS on 53, and HTTPS on 443 for S3 backup uploads.
echo "Step 7: Applying network policies..."
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/security/network-policies.yaml"

# ── Step 8: Backup and restore ConfigMaps ─────────────────────────────────────
# Mounts backup.sh and restore.sh into the CronJob and restore Job containers
# at runtime. Storing scripts in ConfigMaps means updates are applied without
# rebuilding any container image.
echo "Step 8: Applying backup and restore ConfigMaps..."
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/backup/backup-script-configmap.yaml"
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/backup/restore-script-configmap.yaml"

# ── Step 9: Backup CronJob ────────────────────────────────────────────────────
# Renders the CronJob manifest with the correct S3 prefix for the active deploy
# profile (e.g. prod/collections) and applies it. Runs every 6 hours and
# retains the 20 most recent snapshots per collection.
echo "Step 9: Applying backup CronJob..."
bash "${PLATFORM_ROOT}/scripts/render-manifest.sh" backup-cronjob | kubectl apply -f -

# ── Step 10: Wait for rollout ─────────────────────────────────────────────────
# Waits for all StatefulSet pods to reach Ready state before returning.
# Timeout is 600s to accommodate image pulls, volume provisioning, and Raft
# consensus formation on a fresh cluster. Exits with error if any pod fails,
# making this safe to use in CI pipelines.
echo ""
echo "Step 10: Waiting for all pods to be Ready (timeout: 600s)..."
kubectl rollout status statefulset/"${RELEASE_NAME}" -n "${NAMESPACE}" --timeout=600s

echo ""
echo "======================================"
echo " Deployment complete."
echo "======================================"
echo ""
kubectl get pods -n "${NAMESPACE}"
echo ""
echo "Run the following to verify cluster health:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME} 6333:6333"
echo "  curl -s http://127.0.0.1:6333/cluster | python3 -m json.tool"