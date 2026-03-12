#!/bin/sh

set -eu

MODE=${1:-run}
WORKDIR=${WORKDIR:-/restore}
BACKUP_PREFIX=${BACKUP_PREFIX:-snapshots}

if [ -n "${QDRANT_URL:-}" ]; then
  QDRANT_URL=${QDRANT_URL%/}
fi

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

require_env() {
  var_name=$1
  eval "var_value=\${$var_name:-}"

  if [ -z "$var_value" ]; then
    printf 'Missing required environment variable: %s\n' "$var_name" >&2
    exit 1
  fi
}

qdrant_curl() {
  if [ -n "${QDRANT_API_KEY:-}" ]; then
    curl -fsS -H "api-key: ${QDRANT_API_KEY}" "$@"
    return
  fi

  curl -fsS "$@"
}

resolve_snapshot_key() {
  if [ -n "${S3_SNAPSHOT_KEY:-}" ]; then
    printf '%s' "${S3_SNAPSHOT_KEY}"
    return 0
  fi

  require_env SNAPSHOT_FILE
  printf '%s/%s/%s' "${BACKUP_PREFIX}" "${COLLECTION}" "${SNAPSHOT_FILE}"
}

download_snapshot() {
  require_env S3_BUCKET
  require_env AWS_REGION
  require_env COLLECTION

  mkdir -p "${WORKDIR}"

  snapshot_key=$(resolve_snapshot_key)
  snapshot_path="${WORKDIR}/${snapshot_key##*/}"

  log "Downloading s3://${S3_BUCKET}/${snapshot_key}"
  aws s3 cp "s3://${S3_BUCKET}/${snapshot_key}" "${snapshot_path}" --region "${AWS_REGION}"
  printf '%s' "${snapshot_path}" > "${WORKDIR}/.snapshot_path"
}

discover_snapshot_path() {
  if [ -f "${WORKDIR}/.snapshot_path" ]; then
    cat "${WORKDIR}/.snapshot_path"
    return 0
  fi

  if [ -n "${SNAPSHOT_FILE:-}" ] && [ -f "${WORKDIR}/${SNAPSHOT_FILE}" ]; then
    printf '%s' "${WORKDIR}/${SNAPSHOT_FILE}"
    return 0
  fi

  find "${WORKDIR}" -maxdepth 1 -type f ! -name '.snapshot_path' | head -n 1
}

restore_snapshot() {
  require_env QDRANT_URL
  require_env COLLECTION

  snapshot_path=$(discover_snapshot_path)
  if [ -z "${snapshot_path}" ] || [ ! -f "${snapshot_path}" ]; then
    printf 'No snapshot file found in %s\n' "${WORKDIR}" >&2
    exit 1
  fi

  log "Uploading snapshot ${snapshot_path##*/} into collection ${COLLECTION}"
  qdrant_curl -X POST \
    -F "snapshot=@${snapshot_path}" \
    "${QDRANT_URL}/collections/${COLLECTION}/snapshots/upload" >/dev/null
}

case "${MODE}" in
  download)
    download_snapshot
    ;;
  restore)
    restore_snapshot
    ;;
  run)
    download_snapshot
    restore_snapshot
    ;;
  *)
    printf 'Unsupported mode: %s\n' "${MODE}" >&2
    exit 1
    ;;
esac

log "Restore workflow completed."
