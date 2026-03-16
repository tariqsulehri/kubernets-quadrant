# Environment Setup

## Purpose

This document explains how to set up each supported environment in the Qdrant platform repository:

- `local`
- `dev`
- `staging`
- `prod`

It complements:

- `docs/setup.md`
- `docs/operations.md`
- `docs/environment-strategy.md`

## Shared Prerequisites

All environments require:

- `kubectl`
- `helm`
- access to the target Kubernetes cluster
- AWS credentials for backup and restore workflows

Shared repository path:

```bash
cd qdrant-platform
```

Shared secret workflow:

1. prepare `.env`
2. apply Kubernetes secrets
3. deploy the selected profile

Prepare `.env`:

```bash
cp secrets/.env.example secrets/.env
```

Populate:

```bash
AWS_ACCESS_KEY_ID=replace-me
AWS_SECRET_ACCESS_KEY=replace-me
AWS_REGION=us-east-1
S3_BUCKET=tkxel-qdrant-backups
QDRANT_API_KEY=
```

Apply secrets:

```bash
ENV_FILE="$PWD/secrets/.env" bash ./scripts/create-secrets.sh
```

## 1. Local Setup

### Purpose

Use `local` for:

- Minikube development
- quick functional testing
- backup and restore rehearsal

### Expected Characteristics

- single-node deployment
- distributed mode disabled
- `standard` storage class
- minimal resources

### Prerequisites

- Minikube installed
- ingress addon enabled

Start local cluster:

```bash
minikube start
minikube addons enable ingress
```

### Deploy

```bash
DEPLOY_PROFILE=local ./scripts/deploy.sh
```

### Validate

```bash
kubectl get pods -n qdrant
kubectl get pvc -n qdrant
kubectl get ingress -n qdrant
```

### Local Access

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

Use the printed localhost port with:

```bash
curl -H 'Host: qdrant.local' http://127.0.0.1:<PORT>/readyz
```

### Backup Prefix

```text
local/collections
```

## 2. Dev Setup

### Purpose

Use `dev` for:

- shared development testing
- API integration
- low-cost cluster validation

### Expected Characteristics

- lightweight environment
- smaller resources than staging/prod
- simpler operational footprint

### Prerequisites

- reachable development Kubernetes cluster
- storage class named `standard` or an updated value file matching the real cluster
- valid `qdrant-backup-secrets`

### Deploy

```bash
DEPLOY_PROFILE=dev ./scripts/deploy.sh
```

### Validate

```bash
kubectl get pods -n qdrant
kubectl get pvc -n qdrant
kubectl get svc -n qdrant
```

### Backup Prefix

```text
dev/collections
```

## 3. Staging Setup

### Purpose

Use `staging` for:

- production-like validation
- HA rehearsal
- backup and restore testing
- load testing

### Expected Characteristics

- 3-node distributed Qdrant deployment
- production-like ingress
- PodDisruptionBudget enabled
- ServiceMonitor enabled
- dedicated storage classes

### Prerequisites

The cluster must provide:

- at least 3 worker nodes
- storage class `qdrant-fast-ssd`
- storage class `qdrant-snapshots`
- TLS secret `qdrant-staging-tls`
- DNS for `qdrant-staging.tkxel.example.com`
- valid backup secret

### Deploy

```bash
DEPLOY_PROFILE=staging ./scripts/deploy.sh
```

### Validate

```bash
kubectl get pods -n qdrant -o wide
kubectl get pvc -n qdrant
kubectl get pdb -n qdrant
kubectl get ingress -n qdrant
```

Run HA checks:

```bash
EXPECTED_REPLICAS=3 \
MIN_DISTINCT_NODES=3 \
COLLECTION=tkxel_collection \
bash ./scripts/validate-ha.sh
```

### Backup Prefix

```text
staging/collections
```

## 4. Prod Setup

### Purpose

Use `prod` for:

- live client traffic
- durable production deployment
- controlled operational workflows

### Expected Characteristics

- 3 replicas or more
- distributed mode enabled
- zone-aware spreading
- TLS ingress
- monitoring enabled
- dedicated high-performance storage

### Prerequisites

The production cluster must provide:

- at least 3 worker nodes
- production-grade storage class `qdrant-fast-ssd`
- production snapshot storage class `qdrant-snapshots`
- TLS secret `qdrant-prod-tls`
- DNS for `qdrant.tkxel.example.com`
- valid production backup secret
- approved operational access

### Deploy

```bash
DEPLOY_PROFILE=prod ./scripts/deploy.sh
```

### Validate

```bash
kubectl get pods -n qdrant -o wide
kubectl get pvc -n qdrant
kubectl get pdb -n qdrant
kubectl get ingress -n qdrant
kubectl get servicemonitor -n qdrant
```

Run HA validation:

```bash
EXPECTED_REPLICAS=3 \
MIN_DISTINCT_NODES=3 \
COLLECTION=tkxel_collection \
bash ./scripts/validate-ha.sh
```

### Backup Prefix

```text
prod/collections
```

## Deployment Summary

### Local

```bash
DEPLOY_PROFILE=local ./scripts/deploy.sh
```

### Dev

```bash
DEPLOY_PROFILE=dev ./scripts/deploy.sh
```

### Staging

```bash
DEPLOY_PROFILE=staging ./scripts/deploy.sh
```

### Prod

```bash
DEPLOY_PROFILE=prod ./scripts/deploy.sh
```

## Backup and Restore Summary

Backup prefixes:

- `local/collections`
- `dev/collections`
- `staging/collections`
- `prod/collections`

Restore job rendering:

```bash
DEPLOY_PROFILE=prod \
COLLECTION=tkxel_collection \
SNAPSHOT_FILE=replace-me.snapshot \
bash scripts/render-manifest.sh restore-job | kubectl apply -f -
```

## Final Recommendation

Use the environments with this discipline:

- `local` for functional work
- `dev` for integration work
- `staging` for production-like validation
- `prod` for approved releases only

This is the cleanest and most professional operating model for the current repository.
