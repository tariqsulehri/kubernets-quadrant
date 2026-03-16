# Environment Strategy

## Purpose

This document defines the recommended environment separation model for the Qdrant platform.

The goal is to keep development simple, testing realistic, and production safe.

## Recommended Environments

The repository should be operated with four environments:

- `local`
- `dev`
- `staging`
- `prod`

Each environment has a different purpose and should remain isolated from the others.

## Environment Roles

### Local

Purpose:

- developer testing
- local debugging
- basic functional verification

Characteristics:

- Minikube or local Kubernetes
- single-node deployment
- no distributed mode
- low-cost and low-resource settings
- local ingress access

This environment is not intended for:

- HA testing
- production-like validation
- performance conclusions

### Dev

Purpose:

- shared development environment
- feature integration
- API and collection workflow testing

Characteristics:

- low-cost cluster
- smaller resource allocation
- simple operational configuration
- not fully production-like

This environment is useful for:

- application integration
- schema changes
- routine backup workflow checks

### Staging

Purpose:

- production-like validation
- release rehearsal
- backup and restore drills
- HA validation

Characteristics:

- real multi-node cluster
- distributed mode enabled
- same topology pattern as production
- production-like ingress, storage, and policies

This should be the main environment for:

- failover testing
- load testing
- backup verification
- restore verification
- release readiness checks

### Prod

Purpose:

- live production serving
- client-facing traffic
- final durable deployment

Characteristics:

- high availability
- strict operational controls
- controlled access
- monitored and audited operations

This environment should only receive:

- reviewed changes
- validated releases
- tested backup and restore procedures

## Best-Practice Separation Rules

### 1. Separate Clusters

Best practice:

- `local` should be separate from all remote environments
- `staging` should be separate from `prod`

Reason:

- cluster-level isolation is more reliable than namespace-only isolation
- it reduces the chance of production-impacting mistakes

### 2. Separate Storage and Backup Paths

Each environment should have its own backup prefix.

Current model:

- `local/collections`
- `dev/collections`
- `staging/collections`
- `prod/collections`

This prevents:

- backup collision
- accidental cross-environment restore
- confusion during disaster recovery

### 3. Separate Secrets

Each environment must manage secrets independently.

Do not reuse:

- AWS credentials
- API keys
- TLS secrets
- application tokens

Best practice:

- use environment-specific secret stores
- avoid sharing credentials between staging and prod

### 4. Separate Ingress Hosts

Each environment should use a unique hostname.

Examples:

- `qdrant.local`
- `qdrant-dev.tkxel.local`
- `qdrant-staging.tkxel.example.com`
- `qdrant.tkxel.example.com`

This avoids:

- routing confusion
- certificate mismatch
- operational mistakes

### 5. Separate Validation Scope

Each environment should answer a different question:

- `local`: does it work?
- `dev`: does it integrate?
- `staging`: is it safe to release?
- `prod`: is it operating correctly?

This distinction matters because a local success does not prove production readiness.

## What Should Be Tested Where

### Local

Run:

- deployment check
- collection creation
- basic backup test
- basic restore test
- dashboard access

Do not rely on local for:

- HA proof
- realistic storage behavior
- production-like traffic behavior

### Dev

Run:

- application integration testing
- collection schema changes
- functional API checks
- routine backup verification

### Staging

Run:

- final HA validation
- distributed cluster checks
- load test execution
- backup and restore drills
- release candidate validation
- node or pod failure drills

### Prod

Run:

- health checks
- monitored backup jobs
- controlled restore drills
- maintenance validations

Avoid using production for experimental validation.

## Operational Recommendation

The cleanest professional approach for this platform is:

1. use `local` only for development and functional validation
2. use `staging` as the production-like test environment
3. use `prod` only for approved releases
4. keep backup prefixes, secrets, hosts, and storage distinct per environment

## Repository Alignment

The repository already supports this model through:

- profile-based Helm values
- profile-based deployment flow
- environment-specific backup prefixes
- render-based restore and backup manifests

Relevant files:

- `helm/qdrant/values-local.yaml`
- `helm/qdrant/values-dev.yaml`
- `helm/qdrant/values-staging.yaml`
- `helm/qdrant/values-prod.yaml`
- `scripts/deploy.sh`
- `scripts/render-manifest.sh`

## Summary

The best way to keep the platform clean is not to treat `local` as a mini production environment.

Instead:

- keep `local` simple
- keep `staging` production-like
- keep `prod` protected

That separation is the most professional and fault-tolerant operating model for this repository.
