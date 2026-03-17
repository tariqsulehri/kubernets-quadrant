#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLATFORM_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

MANIFEST_NAME=${1:-}
DEPLOY_PROFILE=${DEPLOY_PROFILE:-prod}
COLLECTION=${COLLECTION:-tkxel_collection}
SNAPSHOT_FILE=${SNAPSHOT_FILE:-replace-me.snapshot}
NAMESPACE=${NAMESPACE:-qdrant}

case "${DEPLOY_PROFILE}" in
  local)
    BACKUP_PREFIX="local/collections"
    ;;
  dev)
    BACKUP_PREFIX="dev/collections"
    ;;
  staging)
    BACKUP_PREFIX="staging/collections"
    ;;
  prod)
    BACKUP_PREFIX="prod/collections"
    ;;
  *)
    echo "Unsupported DEPLOY_PROFILE: ${DEPLOY_PROFILE}" >&2
    exit 1
    ;;
esac

case "${MANIFEST_NAME}" in
  backup-cronjob)
    MANIFEST_PATH="${PLATFORM_ROOT}/kubernetes/backup/backup-cronjob.yaml"
    ;;
  restore-job)
    # Jobs have immutable spec fields — kubectl apply fails if the job already
    # exists. Delete any previous restore job before rendering the new one so
    # the caller can safely pipe this output directly to kubectl apply.
    MANIFEST_PATH="${PLATFORM_ROOT}/kubernetes/backup/restore-job.yaml"
    echo "Deleting any existing restore job..." >&2
    kubectl delete job qdrant-restore -n "${NAMESPACE}" --ignore-not-found --wait=true >&2
    ;;
  *)
    echo "Usage: $0 <backup-cronjob|restore-job>" >&2
    exit 1
    ;;
esac

sed \
  -e "s|__BACKUP_PREFIX__|${BACKUP_PREFIX}|g" \
  -e "s|__COLLECTION__|${COLLECTION}|g" \
  -e "s|__SNAPSHOT_FILE__|${SNAPSHOT_FILE}|g" \
  "${MANIFEST_PATH}"