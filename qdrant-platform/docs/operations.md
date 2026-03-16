# Operations

Related documents:

- `docs/setup.md`
- `docs/environment-strategy.md`
- `docs/ha-validation.md`

## Local Minikube Deployment

Deploy the local profile from the `qdrant-platform` directory:

```bash
DEPLOY_PROFILE=local ./scripts/deploy.sh
```

This profile is intended for Minikube and single-node local clusters. It uses:

- `replicaCount: 1`
- `standard` storage for both PVCs
- reduced CPU and memory
- clustering disabled

## Environment Profiles

The repo uses four deployment profiles:

- `local`: Minikube and laptop testing
- `dev`: low-cost shared development environment
- `staging`: production-like verification environment
- `prod`: high-availability production environment

Operational backup prefixes follow the same model:

- `local/collections`
- `dev/collections`
- `staging/collections`
- `prod/collections`

## Local Access

On macOS with the Minikube Docker driver, ingress is exposed through a localhost tunnel instead of direct access to the Minikube VM IP.

Start the tunnel and keep the terminal open:

```bash
minikube service ingress-nginx-controller -n ingress-nginx --url
```

Minikube will print one or more localhost URLs such as:

```text
http://127.0.0.1:50921
```

Use the printed port to test Qdrant from another terminal:

```bash
curl -H 'Host: qdrant.local' http://127.0.0.1:<PORT>/readyz
```

Expected response:

```text
all shards are ready
```

Open the dashboard in a browser:

```text
http://127.0.0.1:<PORT>/dashboard
```

Optional host mapping for cleaner URLs:

```text
127.0.0.1 qdrant.local
```

Then open:

```text
http://qdrant.local:<PORT>/dashboard
```

## Production Deployment

Deploy the production profile with:

```bash
./scripts/deploy.sh
```

Or run Helm directly:

```bash
helm upgrade --install qdrant qdrant/qdrant \
  -n qdrant \
  --create-namespace \
  -f helm/qdrant/values-prod.yaml
```

The deploy script also renders the backup CronJob with the correct prefix for the selected profile.
