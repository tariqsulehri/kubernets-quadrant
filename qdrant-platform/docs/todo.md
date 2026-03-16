# TODO

## Remaining Work

### 1. Final HA Validation in a Real Multi-Node Cluster

Current status:

- HA-oriented architecture is implemented in the repository
- `staging` and `prod` profiles are prepared for distributed deployment
- backup and restore workflows are working
- HA validation tooling and documentation are available

What is still pending:

- validate Qdrant distributed mode on a real multi-node cluster
- confirm 3 replicas are running and ready
- confirm replicas are distributed across distinct nodes
- confirm service remains available during pod failure
- confirm service remains available during node drain
- confirm backup and restore continue to work in the production-like environment

HA should only be considered fully achieved after the runbook in `docs/ha-validation.md` is executed successfully in a real production-like cluster.
