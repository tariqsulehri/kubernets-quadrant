# Kubernetes + Helm Quick Help

This document contains useful commands for working with the Kubernetes
cluster and Helm deployments.

------------------------------------------------------------
SEGMENT 1 — CLUSTER STATUS
------------------------------------------------------------

# Check cluster information
kubectl cluster-info

# Check available nodes
kubectl get nodes

# Check current context
kubectl config current-context

# List all contexts
kubectl config get-contexts

------------------------------------------------------------
SEGMENT 2 — RESOURCE INSPECTION
------------------------------------------------------------

# Show all resources in namespace
kubectl get all

# Show pods
kubectl get pods

# Show services
kubectl get svc

# Show deployments
kubectl get deployments

# Show ingress resources
kubectl get ingress

# Show autoscalers
kubectl get hpa

# Show configmaps
kubectl get configmap


------------------------------------------------------------
SEGMENT 3 — POD OPERATIONS
------------------------------------------------------------

# View logs from pod
kubectl logs <pod-name>

# Follow logs in real time
kubectl logs -f <pod-name>

# Execute shell inside pod
kubectl exec -it <pod-name> -- sh

# Describe pod for troubleshooting
kubectl describe pod <pod-name>

# Restart deployment
kubectl rollout restart deployment <deployment-name>


kubectl exec -it pod/nodapp-deployment-5b696658c6-s8k7p -- wget -qO- http://nodapp-service:3500

------------------------------------------------------------
SEGMENT 4 — SERVICE TESTING
------------------------------------------------------------

# Test service from inside cluster
kubectl exec -it <pod-name> -- wget -qO- http://<service-name>:<port>

# Port forward service locally
kubectl port-forward service/<service-name> 8080:<service-port>

Example

kubectl port-forward service/nodapp-service 8080:3500

Access application

http://localhost:8080


------------------------------------------------------------
SEGMENT 5 — HELM OPERATIONS
------------------------------------------------------------

# Validate Helm chart
helm lint ./helm-chart/nodapp

# Preview generated Kubernetes YAML
helm template nodapp ./helm-chart/nodapp

# Install Helm release
helm install nodapp ./helm-chart/nodapp

# Upgrade release
helm upgrade nodapp ./helm-chart/nodapp

# List Helm releases
helm list

# Show release history
helm history nodapp

# Rollback release
helm rollback nodapp 1

# Remove release
helm uninstall nodapp


------------------------------------------------------------
SEGMENT 6 — DEBUGGING
------------------------------------------------------------

# Describe deployment
kubectl describe deployment <deployment-name>

# Show events
kubectl get events

# Watch pod status changes
kubectl get pods -w

# Check resource usage
kubectl top pods
kubectl top nodes


------------------------------------------------------------
SEGMENT 7 — CLEANUP COMMANDS
------------------------------------------------------------

# Delete deployment
kubectl delete deployment <deployment-name>

# Delete service
kubectl delete service <service-name>

# Delete ingress
kubectl delete ingress <ingress-name>

# Delete autoscaler
kubectl delete hpa <hpa-name>

# Delete configmap
kubectl delete configmap <configmap-name>

# Remove all resources with label
kubectl delete all -l app=<label>


------------------------------------------------------------
SEGMENT 8 — QUICK DEVOPS COMMANDS
------------------------------------------------------------

# Show cluster resources in architecture order
kubectl get deploy,rs,pods,svc,ingress,hpa

# Watch pod status live
kubectl get pods -w

# Show pod environment variables
kubectl exec -it <pod-name> -- printenv

# Show container image used
kubectl get pods -o wide