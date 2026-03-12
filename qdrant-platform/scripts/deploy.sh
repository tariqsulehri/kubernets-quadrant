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

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying ${RELEASE_NAME} into namespace ${NAMESPACE} using ${HELM_VALUES_FILE}"
helm upgrade --install "${RELEASE_NAME}" qdrant/qdrant \
  -n "${NAMESPACE}" \
  -f "${HELM_VALUES_FILE}"

kubectl apply -f "${PLATFORM_ROOT}/kubernetes/security/network-policies.yaml"
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/backup/backup-script-configmap.yaml"
kubectl apply -f "${PLATFORM_ROOT}/kubernetes/backup/restore-script-configmap.yaml"
bash "${PLATFORM_ROOT}/scripts/render-manifest.sh" backup-cronjob | kubectl apply -f -
