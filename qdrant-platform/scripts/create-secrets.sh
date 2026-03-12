#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLATFORM_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ENV_FILE=${ENV_FILE:-"${PLATFORM_ROOT}/secrets/.env"}
NAMESPACE=${NAMESPACE:-qdrant}

prompt_if_empty() {
  local var_name=$1
  local prompt_label=$2
  local secret_input=${3:-false}

  if [[ -n "${!var_name:-}" ]]; then
    return 0
  fi

  if [[ "${secret_input}" == "true" ]]; then
    read -rsp "${prompt_label}: " "${var_name}"
    echo
  else
    read -rp "${prompt_label}: " "${var_name}"
  fi

  export "${var_name}"
}

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

mkdir -p "${PLATFORM_ROOT}/secrets"

prompt_if_empty AWS_ACCESS_KEY_ID "AWS Access Key ID"
prompt_if_empty AWS_SECRET_ACCESS_KEY "AWS Secret Access Key" true
prompt_if_empty AWS_REGION "AWS Region"
prompt_if_empty S3_BUCKET "S3 bucket name"
prompt_if_empty QDRANT_API_KEY "Qdrant API key (optional)"

echo "Creating namespace if it does not exist..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "Applying qdrant-backup-secrets..."
kubectl create secret generic qdrant-backup-secrets \
  --namespace "${NAMESPACE}" \
  --from-literal=AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=AWS_REGION="${AWS_REGION}" \
  --from-literal=S3_BUCKET="${S3_BUCKET}" \
  --dry-run=client -o yaml | kubectl apply -f -

if [[ -n "${QDRANT_API_KEY:-}" ]]; then
  echo "Applying qdrant-secrets..."
  kubectl create secret generic qdrant-secrets \
    --namespace "${NAMESPACE}" \
    --from-literal=QDRANT_API_KEY="${QDRANT_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Secrets available in namespace ${NAMESPACE}:"
kubectl get secrets -n "${NAMESPACE}"
