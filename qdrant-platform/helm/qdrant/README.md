# Qdrant Helm Configuration

This directory contains the shared and environment-specific Helm values for the Qdrant deployment.

Files:

- `values.yaml`: shared defaults
- `values-dev.yaml`: development overrides
- `values-local.yaml`: Minikube and single-node local overrides
- `values-prod.yaml`: production overrides

Examples:

```bash
helm upgrade --install qdrant qdrant/qdrant \
  -n qdrant \
  --create-namespace \
  -f helm/qdrant/values-local.yaml
```

```bash
helm upgrade --install qdrant qdrant/qdrant \
  -n qdrant \
  --create-namespace \
  -f helm/qdrant/values-prod.yaml
```
