# Architecture

The platform deploys Qdrant as a 3-node StatefulSet behind an internal Kubernetes Service and an external NGINX Ingress.

Traffic flow:

Client -> NGINX Ingress -> `qdrant` Service -> Qdrant pods (`qdrant-0`, `qdrant-1`, `qdrant-2`)

Storage model:

- Main vector data is stored on persistent volumes attached to each StatefulSet replica.
- Snapshots are generated through the Qdrant Snapshot API.
- Backup jobs upload those snapshots to the S3 bucket `tkxel-qdrant-backups`.

Operational components:

- Helm values for production live in `helm/qdrant/values-prod.yaml`.
- Backup automation lives in `kubernetes/backup/` and `scripts/backup.sh`.
- Restore automation lives in `kubernetes/backup/restore-job.yaml` and `scripts/restore.sh`.
- Secret templates live in `kubernetes/security/secrets-template.yaml`.
