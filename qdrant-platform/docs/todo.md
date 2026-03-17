# TODO

## Remaining Work

### 1. Final HA Validation in a Real Multi-Node Cluster

Current status:

- HA-oriented architecture is implemented in the repository
- `staging` and `prod` profiles are prepared for distributed deployment
- backup and restore workflows are working
- HA validation tooling and documentation are available

What is still pending: (Below points Completed)
 
- validate Qdrant distributed mode on a real multi-node cluster
- confirm 3 replicas are running and ready
- confirm replicas are distributed across distinct nodes
- confirm service remains available during pod failure
- confirm service remains available during node drain
- confirm backup and restore continue to work in the production-like environment

HA should only be considered fully achieved after the runbook in `docs/ha-validation.md` is executed successfully in a real production-like cluster.


## TODO - Phase- 2 Recommended TODO Items

# 1. Fix Distributed Snapshot in backup.sh
- Why: Current backup captures ~2/3 of data because it snapshots per-node. With replication factor 2 and 3 shards, one node only holds 2 shards. A full backup needs to snapshot each shard from its primary owner.

- What: Update backup.sh to call /collections/{name}/snapshots per shard using the cluster API to identify shard primaries, then merge into a full collection backup.

# 2. Replace Static AWS Credentials with IRSA

- Why: Current setup stores AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as long-lived static keys in a Kubernetes Secret. This is a security risk.

- What: On EKS, configure IAM Roles for Service Accounts (IRSA) so the backup pod assumes an IAM role automatically without any static credentials.


# 3. Validate on a Real Cloud Cluster

- Why: Minikube runs all nodes on a single host. A real zone failure cannot be simulated. The hostpath PVC behavior does not exist on cloud block storage.

- What: Run the full ha-validation.md runbook on a real EKS/GKE/AKS cluster with actual availability zones before production go-live.

# 4. Enable Prometheus Monitoring

- Why: metrics.serviceMonitor.enabled: false in all values files. No alerting exists for shard ManualRecovery, consensus failures, or backup job failures.

- What: Apply kubernetes/monitoring/prometheus.yaml and grafana-dashboard.yaml, enable serviceMonitor in values-prod.yaml, add alerts for cluster health and backup status.

# 5. Enable Qdrant API Key Authentication
- Why: The QDRANT_API_KEY is set in .env and the secret exists in the cluster, but config.service.api_key is commented out in values-prod.yaml. The API is currently unauthenticated.

- What: Uncomment and wire the API key in values-prod.yaml:
yamlconfig:
  service:
    api_key: ${QDRANT_API_KEY}

# 6. Increase Snapshot Frequency

- Why: Current CronJob runs every 6 hours. Any data written in the window between last snapshot and a cluster failure is unrecoverable.

- What: Change CronJob schedule from 0 */6 * * * to 0 */2 * * * (every 2 hours) or implement continuous WAL shipping to S3.

# 7. Validate Ingress Access
- Why: Ingress is configured in values-prod.yaml for qdrant.tkxel.prod.com with TLS, but was never tested. All our testing used port-forward.

- What: Configure DNS, provision TLS certificate, and validate end-to-end access through the NGINX ingress controller.