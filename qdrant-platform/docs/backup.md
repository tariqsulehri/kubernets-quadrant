# Backup

The backup workflow runs as a Kubernetes `CronJob` in the `qdrant` namespace every 6 hours. Each run performs two stages:

1. It calls the Qdrant Snapshot API for every collection and downloads the generated snapshot files into a shared temporary volume.
2. It uploads those files into an environment-specific prefix and removes older objects beyond the configured retention count.

Current prefix mapping:

- `local` -> `local/collections/<collection>/...`
- `dev` -> `dev/collections/<collection>/...`
- `staging` -> `staging/collections/<collection>/...`
- `prod` -> `prod/collections/<collection>/...`

Required resources:

- `kubernetes/backup/backup-script-configmap.yaml`
- `kubernetes/backup/backup-cronjob.yaml`
- `qdrant-backup-secrets`
- Optional `qdrant-secrets` when Qdrant API key authentication is enabled

Required secret keys:

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_REGION`
- `S3_BUCKET`

Optional secret key:

- `QDRANT_API_KEY`

Manual backup test:

```bash
kubectl create job \
  --from=cronjob/qdrant-backup \
  manual-backup \
  -n qdrant
```

Useful verification commands:

```bash
kubectl logs job/manual-backup -n qdrant -c create-snapshots
kubectl logs job/manual-backup -n qdrant -c upload-snapshots
aws s3 ls s3://tkxel-qdrant-backups/prod/collections/ --recursive
```
