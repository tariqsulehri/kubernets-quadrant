## Ingress deployment Command
kubectl apply -f kubernetes/ingress/qdrant-ingress.yaml

## Kubernets Create Secrets

kubectl create secret generic s3-credentials \
--from-literal=AWS_ACCESS_KEY_ID=XXX \
--from-literal=AWS_SECRET_ACCESS_KEY=YYY

## Cleanup Script Exmpale
aws s3 ls s3://qdrant-backups/ | sort | head -n -7 | awk '{print $4}' | xargs -I {} aws s3 rm s3://qdrant-backups/{}


## Required Environment Variables

# Your CronJob must provide:
    - QDRANT_URL
    - S3_BUCKET
    - AWS_ACCESS_KEY_ID
    - AWS_SECRET_ACCESS_KEY
    - AWS_REGION

## DELETE DEPLOYMENT
helm uninstall qdrant -n qdrant 
helm list -n qdrant 

Delete Stateful Resources

Qdrant uses PersistentVolumeClaims that remain after uninstall.

Remove them:

kubectl delete pvc -n qdrant --all

Verify:

kubectl get pvc -n qdrant

# Expected:
No resources found

# Delete Jobs and CronJobs
kubectl delete jobs --all -n qdrant
kubectl delete cronjobs --all -n qdrant

# Delete ConfigMaps
kubectl delete configmap --all -n qdrant


# Delete Old Secrets (Optional)
# Since we recreated them:

kubectl delete secret qdrant-backup-secrets -n qdrant

# Verify Namespace Is Clean
kubectl get all -n qdrant

# Expected:
No resources found


# Configurable Bucket
kubectl create secret generic qdrant-backup-secrets \
  -n qdrant \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="$AWS_REGION" \
  --from-literal=S3_BUCKET="$S3_BUCKET" \
  --dry-run=client -o yaml | kubectl apply -f -


# Fixed Bucket:
kubectl create secret generic qdrant-backup-secrets \
  -n qdrant \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_REGION="$AWS_REGION" \
  --from-literal=S3_BUCKET="tkxel-qdrant-backups" \
  --dry-run=client -o yaml | kubectl apply -f -


# upgrade Helm for local Minikube
helm upgrade --install qdrant qdrant/qdrant \
  -n qdrant \
  --create-namespace \
  -f helm/qdrant/values-local.yaml


# access Qdrant locally on Minikube (keep this terminal open)
minikube service ingress-nginx-controller -n ingress-nginx --url


# example local readiness check from another terminal
curl -H 'Host: qdrant.local' http://127.0.0.1:<PORT>/readyz


# browser example
http://127.0.0.1:<PORT>/dashboard


# optional host mapping for cleaner local URLs
127.0.0.1 qdrant.local


# browser with host mapping
http://qdrant.local:<PORT>/dashboard


# upgrade Helm for production
helm upgrade --install qdrant qdrant/qdrant \
  -n qdrant \
  --create-namespace \
  -f helm/qdrant/values-prod.yaml
