# Troubleshooting Guide

## Purpose

This document provides a practical troubleshooting runbook for the Qdrant platform.

It is organized by symptom so operators can quickly identify:

- likely cause
- commands to run
- expected output
- recommended fix

## Quick Checks

Start with these commands:

```bash
kubectl get pods -n qdrant
kubectl get svc -n qdrant
kubectl get pvc -n qdrant
kubectl get jobs -n qdrant
kubectl get cronjobs -n qdrant
kubectl get ingress -n qdrant

````

````
## PORT FORWARDING:

# Alternative (More Reliable)
# Use Kubernetes port-forward directly:

kubectl port-forward svc/qdrant -n qdrant 6333:6333

# Then test:
curl http://localhost:6333/readyz

# Expected:
all shards are ready

```
## nodes "minikube" is forbidden: User "system:serviceaccount:kube-system:storage-provisioner" 

# cannot get resource "nodes" in API group "" at the cluster scope

kubectl patch clusterrole system:persistent-volume-provisioner \
  --type='json' \
  -p='[{"op":"add","path":"/rules/-","value":{"apiGroups":[""],"resources":["nodes"],"verbs":["get","list","watch"]}}]'


## Best Option for Ingress Testing
   Since your goal is Ingress access (qdrant.tkxel.prod.com), the proper solution is to run:

minikube tunnel

# Leave that terminal running.
Then you can access the ingress normally:

curl http://qdrant.tkxel.prod.com/readyz

# or open:
http://qdrant.tkxel.prod.com/readyz

This makes the ingress IP (192.168.49.2) reachable from your host.



## 1. Pod Is Stuck in Pending

### Symptom

`kubectl get pods -n qdrant`

shows:

- `Pending`

### Likely Causes

- storage class does not exist
- PVC is not bound
- insufficient node resources
- anti-affinity or topology spread rules cannot be satisfied

### Commands

```bash
kubectl describe pod <pod-name> -n qdrant
kubectl get pvc -n qdrant
kubectl get storageclass
```

### Example Real Cause

Local Minikube failed earlier because:

- `fast-ssd` did not exist
- `cold-storage` did not exist

### Fix

For local use:

- deploy with `values-local.yaml`
- use `standard` storage class

For staging or prod:

- create the expected storage classes
- or update Helm values to match real cluster storage classes

## 2. Pod Is Running but Not Ready

### Symptom

Pod status:

- `Running`
- but `READY` is `0/1`

### Commands

```bash
kubectl describe pod <pod-name> -n qdrant
kubectl logs <pod-name> -n qdrant
```

### Likely Causes

- readiness probe failing
- Qdrant still initializing
- config mismatch
- storage not mounted correctly

### Fix

- inspect readiness probe failures
- verify Qdrant listens on port `6333`
- verify the storage and snapshot mounts exist

## 3. Ingress Is Not Reachable

### Symptom

Dashboard or readiness URL is not accessible.

### Commands

```bash
kubectl get ingress -n qdrant
kubectl describe ingress qdrant -n qdrant
kubectl get pods -A | grep ingress
kubectl get svc -A | grep ingress
```

For Minikube on macOS:

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

### Likely Causes

- ingress controller not installed
- wrong host mapping
- wrong local tunnel port
- Minikube Docker driver tunnel not running

### Fix

For local Minikube:

1. run:

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

2. keep the terminal open
3. use the printed localhost port
4. map `qdrant.local` to `127.0.0.1` if using hostname-based access

## 4. Backup Job Fails

### Symptom

Manual backup job fails or CronJob does not complete.

### Commands

```bash
kubectl get jobs -n qdrant
kubectl describe job manual-backup -n qdrant
kubectl get pods -n qdrant -l job-name=manual-backup
kubectl logs <pod-name> -n qdrant -c create-snapshots
kubectl logs <pod-name> -n qdrant -c upload-snapshots
```

### Likely Causes

- invalid AWS credentials
- missing secret values
- wrong bucket region
- no snapshot files produced

### Specific Checks

Check secret keys:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
```

Check AWS values are not empty:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_REGION}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.S3_BUCKET}' | wc -c
```

### Real Failure Seen During Validation

We observed:

```text
InvalidAccessKeyId
```

This means the job logic was correct, but AWS credentials were invalid.

### Fix

Recreate the secret with real values:

```bash
kubectl create secret generic qdrant-backup-secrets \
  -n qdrant \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="$AWS_REGION" \
  --from-literal=S3_BUCKET="tkxel-qdrant-backups" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Then rerun:

```bash
kubectl delete job manual-backup -n qdrant --ignore-not-found
kubectl create job --from=cronjob/qdrant-backup manual-backup -n qdrant
```

## 5. Restore Job Fails

### Symptom

Restore pod does not complete.

### Commands

```bash
kubectl get job qdrant-restore -n qdrant
kubectl describe job qdrant-restore -n qdrant
kubectl get pods -n qdrant -l job-name=qdrant-restore
kubectl logs <pod-name> -n qdrant -c download-snapshot
kubectl logs <pod-name> -n qdrant -c restore-collection
```

### Likely Causes

- wrong snapshot file name
- wrong environment prefix
- empty or invalid AWS secret
- snapshot does not exist in S3
- placeholder values still present in the restore job

### Fix

Render the restore job with real values:

```bash
DEPLOY_PROFILE=prod \
COLLECTION=tkxel_collection \
SNAPSHOT_FILE=replace-me.snapshot \
bash scripts/render-manifest.sh restore-job | kubectl apply -f -
```

Use the actual snapshot file name from S3.

## 6. No Manual Backup Pod Appears

### Symptom

```bash
kubectl get pods -n qdrant -l job-name=manual-backup
```

returns:

```text
No resources found
```

### Meaning

This usually means:

- the job does not exist
- the job already failed and its pod was deleted
- the job completed and the pod is gone

### Commands

```bash
kubectl get job manual-backup -n qdrant
kubectl describe job manual-backup -n qdrant
kubectl get events -n qdrant --sort-by=.lastTimestamp | tail -n 40
```

### Fix

Delete and recreate the manual job:

```bash
kubectl delete job manual-backup -n qdrant --ignore-not-found
kubectl create job --from=cronjob/qdrant-backup manual-backup -n qdrant
```

## 7. Distributed Mode Is Not Enabled

### Symptom

Qdrant reports:

```text
Distributed mode is not enabled for this cluster
```

### Meaning

This is expected in:

- `local`
- `dev` if configured as single-node

It is not expected in:

- `staging`
- `prod`

### Commands

```bash
kubectl get statefulset qdrant -n qdrant
kubectl get pods -n qdrant -o wide
```

Check the deployed profile values.

### Fix

Use:

- `values-staging.yaml`
- `values-prod.yaml`

These enable:

- `replicaCount: 3`
- distributed cluster mode

## 8. HA Validation Fails

### Symptom

`scripts/validate-ha.sh` returns a failure.

### Commands

```bash
bash scripts/validate-ha.sh
kubectl get statefulset qdrant -n qdrant
kubectl get pods -n qdrant -o wide
kubectl get pvc -n qdrant
kubectl get pdb -n qdrant
```

### Likely Causes

- not enough replicas
- pods not spread across nodes
- cluster API not reporting peers
- PVC issues
- local environment being used instead of staging/prod

### Fix

- run HA validation only on staging or prod-like multi-node clusters
- verify actual node count
- verify storage classes
- verify the production-like profile is deployed

## 9. Load Test Fails

### Symptom

`tests/load-test.py` exits with connection or HTTP errors.

### Commands

```bash
kubectl port-forward -n qdrant svc/qdrant 6333:6333
python3 tests/load-test.py --help
```

### Likely Causes

- port-forward not running
- Qdrant not ready
- collection already exists with incompatible settings

### Fix

- verify port-forward
- verify `/readyz`
- use a new collection name for the test

## 10. Secret Values Need Verification

### Commands

Check presence:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
```

Check decoded values:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_REGION}' | base64 --decode; echo
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.S3_BUCKET}' | base64 --decode; echo
```

Check without revealing the values:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.AWS_REGION}' | wc -c
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data.S3_BUCKET}' | wc -c
```

## Recommended Debug Flow

When something fails, use this order:

1. check pods
2. check PVCs
3. check job status
4. inspect logs
5. inspect secrets
6. inspect events
7. rerun only after root cause is clear

## Related Documents

- `docs/setup.md`
- `docs/operations.md`
- `docs/environment-strategy.md`
- `docs/ha-validation.md`

## Summary

This runbook is designed to make day-to-day debugging faster and less ad hoc.

If a deployment, backup, restore, ingress route, or HA check fails, start here first.


## Troubleshooting
# Pods stuck Pending:
bashkubectl describe pod qdrant-0 -n qdrant | tail -20
kubectl get pvc -n qdrant
kubectl get storageclass

# Most likely cause: RBAC or storage class not applied. Re-run 
deploy.sh — it is idempotent.

# PVC ProvisioningFailed — nodes forbidden:

bashkubectl apply -f kubernetes/rbac/storage-provisioner-rbac.yaml
kubectl delete pvc -n qdrant --all
kubectl delete pod -n qdrant qdrant-0 qdrant-1 qdrant-2

# Pods Pending with no events:
bashkubectl get nodes --show-labels | grep topology.kubernetes.io/zone

# If missing, re-run: bash scripts/label-nodes.sh
# Backup job fails:

bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
kubectl describe job manual-backup -n qdrant

# Restore job fails:
bashkubectl logs <restore-pod> -n qdrant -c download-snapshot
kubectl logs <restore-pod> -n qdrant -c restore-collection