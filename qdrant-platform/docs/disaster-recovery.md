# Disaster Recovery

Recovery uses a one-off Kubernetes `Job` that downloads a chosen snapshot from S3 and uploads it back into the target Qdrant collection.

Preparation:

1. Confirm the target collection name.
2. Identify the snapshot file name to restore under the environment prefix, for example `prod/collections/<collection>/<snapshot-file>.snapshot`.
3. Render the restore job with the target profile, collection, and snapshot file.

Run the restore:

```bash
DEPLOY_PROFILE=prod \
COLLECTION=tkxel_collection \
SNAPSHOT_FILE=replace-me.snapshot \
bash scripts/render-manifest.sh restore-job | kubectl apply -f -

kubectl logs job/qdrant-restore -n qdrant -c download-snapshot
kubectl logs job/qdrant-restore -n qdrant -c restore-collection
```

Operational notes:

- The restore job expects `qdrant-backup-secrets` to exist.
- If Qdrant API authentication is enabled, create `qdrant-secrets` with `QDRANT_API_KEY`.
- Restores are collection-scoped. Restore each collection snapshot explicitly.
- Test restore procedures in a non-production namespace before using them in production.
