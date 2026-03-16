# HA Validation

## Purpose

This document defines the final high-availability validation process for a real multi-node, production-like Qdrant cluster.

The goal is to prove that the platform can:

- run as a distributed Qdrant cluster
- tolerate pod or node disruption
- preserve service availability
- keep backups operational
- restore from S3 successfully
- handle write and read traffic during validation

## Target Environment

Run this validation only on a real multi-node cluster, not on Minikube.

Recommended baseline:

- Kubernetes cluster with at least 3 worker nodes
- one Qdrant pod per node
- distributed mode enabled
- staging or prod Helm profile
- valid TLS, storage classes, and backup secrets

Recommended profiles:

- `staging` for rehearsal
- `prod` for final sign-off

## Pre-Validation Requirements

Before running HA validation, confirm:

- `values-staging.yaml` or `values-prod.yaml` is deployed
- Qdrant has 3 replicas
- all PVCs are bound
- `qdrant-backup-secrets` is valid
- ingress and service routing are healthy
- at least one collection exists for validation

Suggested validation collection:

- `tkxel_collection`

## Step 1. Deploy the Target Environment

Example for staging:

```bash
cd qdrant-platform
DEPLOY_PROFILE=staging ./scripts/deploy.sh
```

Example for production:

```bash
cd qdrant-platform
DEPLOY_PROFILE=prod ./scripts/deploy.sh
```

## Step 2. Run Non-Destructive HA Checks

Use the HA validation script:

```bash
cd qdrant-platform
EXPECTED_REPLICAS=3 \
MIN_DISTINCT_NODES=3 \
COLLECTION=tkxel_collection \
bash ./scripts/validate-ha.sh
```

This script validates:

- StatefulSet replica count
- ready replica count
- pod readiness
- node distribution
- PVC binding
- PodDisruptionBudget presence
- Qdrant readiness endpoint
- distributed cluster endpoint
- collection endpoint reachability

## Step 3. Run Write and Query Load

Port-forward the service:

```bash
kubectl port-forward -n qdrant svc/qdrant 6333:6333
```

In another terminal, run the load test:

```bash
cd qdrant-platform
python3 tests/load-test.py \
  --base-url http://127.0.0.1:6333 \
  --collection ha_validation_collection \
  --vector-size 4 \
  --points 300 \
  --batch-size 50 \
  --search-rounds 25 \
  --shard-number 3 \
  --replication-factor 2
```

Expected outcome:

- points are inserted successfully
- search requests succeed consistently
- collection remains healthy

## Step 4. Validate Backup in the Target Environment

Run a manual backup:

```bash
kubectl delete job manual-backup -n qdrant --ignore-not-found
kubectl create job --from=cronjob/qdrant-backup manual-backup -n qdrant
kubectl wait --for=condition=complete job/manual-backup -n qdrant --timeout=180s
```

Check the pod logs:

```bash
pod=$(kubectl get pods -n qdrant -l job-name=manual-backup -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$pod" -n qdrant -c create-snapshots
kubectl logs "$pod" -n qdrant -c upload-snapshots
```

Confirm the snapshot exists in S3 using the correct environment prefix:

- `staging/collections/...`
- `prod/collections/...`

## Step 5. Validate Restore from S3

Render the restore job with the correct snapshot file:

```bash
DEPLOY_PROFILE=staging \
COLLECTION=tkxel_collection \
SNAPSHOT_FILE=replace-me.snapshot \
bash scripts/render-manifest.sh restore-job | kubectl apply -f -
```

Wait for completion:

```bash
kubectl wait --for=condition=complete job/qdrant-restore -n qdrant --timeout=180s
```

Check logs:

```bash
pod=$(kubectl get pods -n qdrant -l job-name=qdrant-restore -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$pod" -n qdrant -c download-snapshot
kubectl logs "$pod" -n qdrant -c restore-collection
```

## Step 6. Perform Failure Drills

These drills should be performed one at a time.

### Drill A. Delete One Qdrant Pod

```bash
kubectl delete pod qdrant-1 -n qdrant
```

Validate:

- service remains available
- surviving pods remain ready
- deleted pod is recreated
- cluster returns to ready state

### Drill B. Drain One Worker Node

Example:

```bash
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

Validate:

- Qdrant still serves requests
- remaining replicas stay healthy
- PDB prevents unsafe disruption

After the drill:

```bash
kubectl uncordon <node-name>
```

### Drill C. Backup During Cluster Operation

Run a manual backup while the cluster is healthy and serving queries.

Validate:

- backup completes
- snapshots upload successfully
- no application outage occurs

## Acceptance Criteria

The HA validation is successful only if all of the following are true:

- 3 Qdrant replicas are running and ready
- replicas are distributed across 3 distinct nodes
- distributed mode is enabled
- collection API remains available during pod disruption
- manual backup succeeds
- restore job succeeds
- collection data remains accessible after restore
- no unsafe voluntary disruption is allowed by policy

## Recommended Evidence to Capture

Capture the following for sign-off:

- `kubectl get pods -n qdrant -o wide`
- `kubectl get pvc -n qdrant`
- `kubectl get pdb -n qdrant`
- output of `scripts/validate-ha.sh`
- load test output
- backup job logs
- restore job logs
- snapshot key stored in S3

## Notes

- Run the full procedure in `staging` before running it in `prod`.
- Do not perform node drain testing in production without an approved maintenance window.
- Prefer non-destructive checks first, then controlled failure drills.

## Result

When this runbook passes, the platform has moved from local and functional validation into real HA operational validation for a production-like cluster.
