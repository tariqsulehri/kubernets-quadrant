# Disaster Recovery

Recovery uses a one-off Kubernetes `Job` that downloads a chosen snapshot from S3 and uploads it back into the target Qdrant collection.

Preparation:

1. Confirm the target collection name.
2. Identify the full S3 object key for the snapshot to restore.
3. Edit `kubernetes/backup/restore-job.yaml` and update `COLLECTION` plus `S3_SNAPSHOT_KEY`.

Run the restore:

```bash
kubectl apply -f kubernetes/backup/restore-job.yaml
kubectl logs job/qdrant-restore -n qdrant -c download-snapshot
kubectl logs job/qdrant-restore -n qdrant -c restore-collection
```

Operational notes:

- The restore job expects `qdrant-backup-secrets` to exist.
- If Qdrant API authentication is enabled, create `qdrant-secrets` with `QDRANT_API_KEY`.
- Restores are collection-scoped. Restore each collection snapshot explicitly.
- Test restore procedures in a non-production namespace before using them in production.
