# Deploy Qdrant from Scratch

Tested on: multi-node Minikube, `feature-v02` branch, `prod` profile.

---

## Prerequisites

```bash
minikube version
kubectl version --client
helm version
aws --version
python3 --version
```

Add the Qdrant Helm repo:

```bash
helm repo add qdrant https://qdrant.github.io/qdrant-helm
helm repo update
```

---

## Step 1 — Start Minikube (3 nodes)

```bash
minikube start --nodes=3
minikube addons enable ingress
```

Verify all nodes are Ready:

```bash
kubectl get nodes
```

Expected:
```
NAME           STATUS   ROLES           AGE
minikube       Ready    control-plane   Xm
minikube-m02   Ready    <none>          Xm
minikube-m03   Ready    <none>          Xm
```

---

## Step 2 — Clone the Repo and Enter Platform Directory

```bash
git clone <repo-url>
cd kubernets-qdrant/qdrant-platform
```

---

## Step 3 — Prepare Secrets

```bash
cp secrets/.env.example secrets/.env
```

Edit `secrets/.env` with real values:

```bash
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
S3_BUCKET=tkxel-qdrant-backups
QDRANT_API_KEY=your-api-key
```

Apply secrets to the cluster:

```bash
ENV_FILE="$PWD/secrets/.env" bash scripts/create-secrets.sh
```

Verify:

```bash
kubectl get secrets -n qdrant
```

Expected:
```
qdrant-backup-secrets
qdrant-secrets
```

---

## Step 4 — Deploy

```bash
DEPLOY_PROFILE=prod bash scripts/deploy.sh
```

This single command does the following in order:

1. Applies RBAC fix — grants storage provisioner permission to read nodes (fixes PVC Pending on multi-node Minikube)
2. Applies storage classes — `qdrant-fast-ssd` and `qdrant-snapshots`
3. Labels nodes with zone topology — required for prod pod spread constraints
4. Creates the `qdrant` namespace
5. Deploys Qdrant via Helm using `values-prod.yaml`
6. Applies network policies
7. Applies backup and restore ConfigMaps
8. Renders and applies the backup CronJob
9. Waits for all pods to be Ready

---

## Step 5 — Verify Deployment

```bash
# All 3 pods Running
kubectl get pods -n qdrant

# All 6 PVCs Bound (storage + snapshots x3)
kubectl get pvc -n qdrant

# Cluster consensus healthy
kubectl port-forward -n qdrant svc/qdrant 6333:6333 &
curl -s http://127.0.0.1:6333/cluster | python3 -m json.tool
```

Expected cluster response:
```json
{
    "result": {
        "status": "enabled",
        "peers": { "...3 peers listed..." },
        "raft_info": {
            "pending_operations": 0,
            "message_send_failures": {}
        }
    },
    "status": "ok"
}
```

---

## Step 6 — Load Test

```bash
python3 tests/load-test.py \
  --base-url http://127.0.0.1:6333 \
  --collection tkxel_collection \
  --points 300 \
  --batch-size 50 \
  --search-rounds 25 \
  --shard-number 3 \
  --replication-factor 2
```

Expected results:
```
Load test completed successfully.
Collection: tkxel_collection
Points reported by Qdrant: 300
Write batches: 6
Average write latency: ~0.01s
P95 write latency: ~0.03s
Search rounds: 25
Average search latency: ~0.008s
P95 search latency: ~0.012s
Search result sizes: min=5, max=5
```

---

## Step 7 — Backup

Trigger a manual backup:

```bash
kubectl delete job manual-backup -n qdrant --ignore-not-found
kubectl create job --from=cronjob/qdrant-backup manual-backup -n qdrant
kubectl wait --for=condition=complete job/manual-backup -n qdrant --timeout=180s
```

Check logs:

```bash
pod=$(kubectl get pods -n qdrant -l job-name=manual-backup -o jsonpath='{.items[0].metadata.name}')
kubectl logs $pod -n qdrant -c create-snapshots
kubectl logs $pod -n qdrant -c upload-snapshots
```

Confirm snapshot exists in S3:

```bash
aws s3 ls s3://tkxel-qdrant-backups/prod/collections/ --recursive --region us-east-1
```

Note the snapshot filename — you will need it for the restore step.

---

## Step 8 — Restore

Delete the collection to simulate data loss:

```bash
curl -X DELETE http://127.0.0.1:6333/collections/tkxel_collection
curl -s http://127.0.0.1:6333/collections | python3 -m json.tool
```

Restore from S3 snapshot (replace `<snapshot-file>` with the filename from Step 7):

```bash
DEPLOY_PROFILE=prod \
COLLECTION=tkxel_collection \
SNAPSHOT_FILE=<snapshot-file>.snapshot \
bash scripts/render-manifest.sh restore-job | kubectl apply -f -

kubectl wait --for=condition=complete job/qdrant-restore -n qdrant --timeout=180s
```

Check restore logs:

```bash
pod=$(kubectl get pods -n qdrant -l job-name=qdrant-restore -o jsonpath='{.items[0].metadata.name}')
kubectl logs $pod -n qdrant -c download-snapshot
kubectl logs $pod -n qdrant -c restore-collection
```

Verify data is back:

```bash
curl -s http://127.0.0.1:6333/collections/tkxel_collection | python3 -m json.tool | grep points_count
```

Expected: `"points_count": 300`

---

## Teardown

```bash
helm uninstall qdrant -n qdrant
kubectl delete pvc -n qdrant --all
kubectl delete jobs --all -n qdrant
kubectl delete cronjobs --all -n qdrant
kubectl delete configmap --all -n qdrant
kubectl delete secret qdrant-backup-secrets qdrant-secrets -n qdrant
kubectl delete namespace qdrant
```

Verify clean:

```bash
kubectl get all -n qdrant
# Expected: No resources found
```

---

## Troubleshooting

**Pods stuck Pending:**
```bash
kubectl describe pod qdrant-0 -n qdrant | tail -20
kubectl get pvc -n qdrant
kubectl get storageclass
```

Most likely cause: RBAC or storage class not applied. Re-run `deploy.sh` — it is idempotent.

**PVC ProvisioningFailed — nodes forbidden:**
```bash
kubectl apply -f kubernetes/rbac/storage-provisioner-rbac.yaml
kubectl delete pvc -n qdrant --all
kubectl delete pod -n qdrant qdrant-0 qdrant-1 qdrant-2
```

**Pods Pending with no events:**
```bash
kubectl get nodes --show-labels | grep topology.kubernetes.io/zone
```
If missing, re-run: `bash scripts/label-nodes.sh`

**Backup job fails:**
```bash
kubectl get secret qdrant-backup-secrets -n qdrant -o jsonpath='{.data}'
kubectl describe job manual-backup -n qdrant
```

**Restore job fails:**
```bash
kubectl logs <restore-pod> -n qdrant -c download-snapshot
kubectl logs <restore-pod> -n qdrant -c restore-collection
```