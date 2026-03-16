# Setup Guide

Related documents:

- `docs/operations.md`
- `docs/environment-strategy.md`
- `docs/ha-validation.md`

## Overview

This guide explains how to set up, configure, deploy, and verify the Qdrant platform from the current branch:

```text
feature-v02
```

It is written for the current repository structure and scripts in `qdrant-platform/`.

## Repository Layout

Main working directory:

```text
qdrant-platform/
```

Important paths:

- `helm/qdrant/`: Helm values for each environment
- `kubernetes/backup/`: backup and restore manifests
- `kubernetes/security/`: secret templates and network policies
- `scripts/`: deployment, secret, and manifest rendering scripts
- `docs/`: platform documentation

## Prerequisites

Install and verify:

- `kubectl`
- `helm`
- `minikube` for local setup
- access to an AWS S3 bucket for backup tests

Recommended local checks:

```bash
kubectl version --client
helm version
minikube version
```

If using Minikube locally, start the cluster and enable ingress:

```bash
minikube start
minikube addons enable ingress
```

## Environment Profiles

The repository supports four deployment profiles:

- `local`
- `dev`
- `staging`
- `prod`

Profile files:

- `helm/qdrant/values-local.yaml`
- `helm/qdrant/values-dev.yaml`
- `helm/qdrant/values-staging.yaml`
- `helm/qdrant/values-prod.yaml`

Recommended usage:

- `local`: Minikube and laptop verification
- `dev`: low-cost shared development cluster
- `staging`: production-like validation cluster
- `prod`: production deployment

## Step 1. Move Into the Platform Directory

```bash
cd qdrant-platform
```

## Step 2. Prepare Secrets

Create a local environment file from the example:

```bash
cp secrets/.env.example secrets/.env
```

Populate it with real values:

```bash
AWS_ACCESS_KEY_ID=replace-me
AWS_SECRET_ACCESS_KEY=replace-me
AWS_REGION=us-east-1
S3_BUCKET=tkxel-qdrant-backups
QDRANT_API_KEY=
```

Apply Kubernetes secrets:

```bash
ENV_FILE="$PWD/secrets/.env" bash ./scripts/create-secrets.sh
```

What this creates:

- `qdrant-backup-secrets`
- optional `qdrant-secrets`

Basic secret verification:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
```

## Step 3. Choose the Deployment Profile

For local Minikube:

```bash
export DEPLOY_PROFILE=local
```

For shared development:

```bash
export DEPLOY_PROFILE=dev
```

For staging:

```bash
export DEPLOY_PROFILE=staging
```

For production:

```bash
export DEPLOY_PROFILE=prod
```

## Step 4. Deploy Qdrant

Deploy using the repository script:

```bash
./scripts/deploy.sh
```

This script:

1. creates the namespace if needed
2. selects the Helm values file for the active `DEPLOY_PROFILE`
3. deploys Qdrant through Helm
4. applies network policies
5. applies backup and restore script ConfigMaps
6. renders and applies the backup CronJob with the correct S3 prefix

## Step 5. Verify the Deployment

Check pods:

```bash
kubectl get pods -n qdrant
```

Check services:

```bash
kubectl get svc -n qdrant
```

Check PVCs:

```bash
kubectl get pvc -n qdrant
```

Expected for a healthy local deployment:

- Qdrant pod is `Running`
- PVCs are `Bound`

## Step 6. Access Qdrant Locally

On macOS with the Minikube Docker driver, run:

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

Keep that terminal open.

Minikube will print a local forwarding URL such as:

```text
http://127.0.0.1:52061
```

Test readiness:

```bash
curl -H 'Host: qdrant.local' http://127.0.0.1:<PORT>/readyz
```

Expected response:

```text
all shards are ready
```

Open the dashboard:

```text
http://127.0.0.1:<PORT>/dashboard
```

Optional host mapping:

```text
127.0.0.1 qdrant.local
```

Then use:

```text
http://qdrant.local:<PORT>/dashboard
```

## Step 7. Basic Functional Tests

### Test 1. Create a Collection

Port-forward the Qdrant service:

```bash
kubectl port-forward -n qdrant svc/qdrant 6333:6333
```

In another terminal, create a collection:

```bash
curl -X PUT http://127.0.0.1:6333/collections/tkxel_collection \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 4,
      "distance": "Cosine"
    },
    "shard_number": 1,
    "replication_factor": 1
  }'
```

Check collections:

```bash
curl http://127.0.0.1:6333/collections
```

### Test 2. Run a Manual Backup

Create a one-off backup job from the CronJob:

```bash
kubectl delete job manual-backup -n qdrant --ignore-not-found
kubectl create job --from=cronjob/qdrant-backup manual-backup -n qdrant
```

Wait for completion:

```bash
kubectl wait --for=condition=complete job/manual-backup -n qdrant --timeout=180s
```

Check logs:

```bash
pod=$(kubectl get pods -n qdrant -l job-name=manual-backup -o jsonpath='{.items[0].metadata.name}')
kubectl logs "$pod" -n qdrant -c create-snapshots
kubectl logs "$pod" -n qdrant -c upload-snapshots
```

Confirm the snapshot exists in S3:

```bash
aws s3 ls s3://tkxel-qdrant-backups/prod/collections/ --recursive --region us-east-1
```

Adjust the prefix for non-production profiles:

- `local/collections`
- `dev/collections`
- `staging/collections`
- `prod/collections`

### Test 3. Run a Manual Restore

Render the restore job with the collection and snapshot file:

```bash
DEPLOY_PROFILE=prod \
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

## Production Notes

Before using `staging` or `prod`, make sure the cluster has:

- valid storage classes referenced by the values files
- valid TLS secrets referenced by ingress
- valid DNS records
- real AWS backup credentials

Production-specific expectations:

- multi-node Kubernetes cluster
- Qdrant distributed mode enabled
- backup bucket versioning recommended
- no long-lived static cloud credentials in pods if IRSA or workload identity is available

## Troubleshooting

If pods are `Pending`:

```bash
kubectl describe pod <pod-name> -n qdrant
kubectl get pvc -n qdrant
kubectl get storageclass
```

If backup fails:

```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
kubectl describe job manual-backup -n qdrant
```

If restore fails:

```bash
kubectl describe job qdrant-restore -n qdrant
kubectl logs <restore-pod-name> -n qdrant -c download-snapshot
kubectl logs <restore-pod-name> -n qdrant -c restore-collection
```

If ingress is unreachable locally:

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

Use the printed localhost port rather than the Minikube VM IP when using the Docker driver on macOS.

## Outcome

After following this guide, you should have:

- Qdrant deployed on Kubernetes
- environment-specific configuration in place
- working local access
- a test collection created
- a verified backup path to S3
- a verified restore path from S3

This is the current baseline for the repository on `feature-v02`.
