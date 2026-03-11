# Node Kubernetes Application Deployment

This repository contains a **Helm-based Kubernetes deployment** for a Node.js application.

The project demonstrates a **production-ready Kubernetes architecture** including:

- Deployment
- Service
- Ingress
- ConfigMap
- Horizontal Pod Autoscaler (HPA)
- Helm Chart configuration

------------------------------------------------------------

# SEGMENT 1 — PROJECT OVERVIEW

This project deploys a **Node.js application** into a Kubernetes cluster using **Helm**.

The deployment supports:

- scalable architecture
- configurable environment variables
- automatic scaling
- external access through Ingress
- infrastructure managed through Helm templates

All configuration is controlled using:

values.yaml

This allows changing deployment behavior without modifying templates.

------------------------------------------------------------

# SEGMENT 2 — ARCHITECTURE

Application traffic flows through the following components:

User Request
      ↓
Ingress Controller
      ↓
Kubernetes Service
      ↓
Deployment
      ↓
Pods (Node.js Application)

Example flow:

Browser → Ingress → Service → Pods

------------------------------------------------------------

# SEGMENT 3 — PROJECT STRUCTURE

project-root/

│
├── helm-chart/
│   └── nodapp/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── ingress.yaml
│           ├── configmap.yaml
│           └── hpa.yaml
│
├── commands.md
│
└── README.md

Explanation:

Chart.yaml  
Defines chart metadata such as version and name.

values.yaml  
Central configuration file for the deployment.

templates/  
Contains Kubernetes resource templates used by Helm.

commands.md  
Contains operational commands for deployment and troubleshooting.

------------------------------------------------------------

# SEGMENT 4 — PREREQUISITES

Before deployment ensure the following tools are installed.

Required tools:

Kubernetes  
Helm  
Docker  
kubectl

Verify installation:

kubectl version
helm version
docker --version

Verify cluster:

kubectl get nodes

------------------------------------------------------------

# SEGMENT 5 — HELM CHART CONFIGURATION

All runtime configuration is defined in:

values.yaml

Examples of configurable parameters:

replica count
image version
service port
ingress domain
resource limits
autoscaling configuration

Example values:

replicaCount: 2

image:
  repository: tariqsulehri/nodapp-k8s
  tag: latest

service:
  type: ClusterIP
  port: 3500

------------------------------------------------------------

# SEGMENT 6 — DEPLOYMENT STEPS

Step 1 — Validate Helm chart

helm lint ./helm-chart/nodapp

Step 2 — Render templates

helm template nodapp ./helm-chart/nodapp

Step 3 — Deploy application

helm install nodapp ./helm-chart/nodapp

Verify deployment:

kubectl get pods
kubectl get svc
kubectl get ingress
kubectl get hpa

------------------------------------------------------------

# SEGMENT 7 — ACCESS APPLICATION

If using local Kubernetes (Minikube):

Add domain mapping:

sudo nano /etc/hosts

Add entry:

127.0.0.1 nodapp.local

Open browser:

http://nodapp.local

------------------------------------------------------------

# SEGMENT 8 — SCALING APPLICATION

Horizontal Pod Autoscaler automatically scales Pods based on CPU usage.

Example configuration:

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 6
  targetCPUUtilizationPercentage: 75

Check autoscaler:

kubectl get hpa

------------------------------------------------------------

# SEGMENT 9 — APPLICATION UPDATE

Upgrade deployment after changes:

helm upgrade nodapp ./helm-chart/nodapp

Example updating image:

helm upgrade nodapp ./helm-chart/nodapp \
--set image.tag=v2

------------------------------------------------------------

# SEGMENT 10 — MONITORING

View running Pods:

kubectl get pods

View application logs:

kubectl logs -l app=nodapp

Monitor resources:

kubectl top pods

------------------------------------------------------------

# SEGMENT 11 — TROUBLESHOOTING

Check Pod details:

kubectl describe pod <pod-name>

Check Deployment:

kubectl describe deployment nodapp-deployment

Check autoscaling:

kubectl describe hpa nodapp-hpa

------------------------------------------------------------

# SEGMENT 12 — ROLLBACK DEPLOYMENT

If a deployment fails:

helm history nodapp

Rollback to previous version:

helm rollback nodapp 1

------------------------------------------------------------

# SEGMENT 13 — REMOVE APPLICATION

Remove Helm release:

helm uninstall nodapp

Verify removal:

kubectl get pods

------------------------------------------------------------

# SEGMENT 14 — DEPLOYMENT WORKFLOW

Typical CI/CD workflow:

Developer pushes code
        ↓
Docker image built
        ↓
Image pushed to registry
        ↓
values.yaml updated
        ↓
Helm upgrade executed
        ↓
Kubernetes performs rolling update

------------------------------------------------------------

# SEGMENT 15 — TECHNOLOGIES USED

Kubernetes  
Helm  
Docker  
Node.js  
Ingress Controller  
Horizontal Pod Autoscaler

------------------------------------------------------------

# SEGMENT 16 — QUICK START

Deploy application:

helm install nodapp ./helm-chart/nodapp

Access application:

http://nodapp.local