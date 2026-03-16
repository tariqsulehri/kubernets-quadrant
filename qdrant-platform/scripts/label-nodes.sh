#!/bin/bash

set -euo pipefail

# Assigns topology.kubernetes.io/zone labels to all nodes in the cluster.
# Required for Qdrant prod topology spread constraints to work.
# Zones are assigned round-robin: zone-a, zone-b, zone-c

ZONES=("zone-a" "zone-b" "zone-c")

nodes=($(kubectl get nodes --no-headers -o custom-columns=":metadata.name"))

echo "Found ${#nodes[@]} node(s). Assigning zone labels..."

for i in "${!nodes[@]}"; do
  node="${nodes[$i]}"
  zone="${ZONES[$((i % ${#ZONES[@]}))]}"
  echo "Labeling node ${node} -> topology.kubernetes.io/zone=${zone}"
  kubectl label node "${node}" topology.kubernetes.io/zone="${zone}" --overwrite
done

echo "Node zone labels applied successfully."
kubectl get nodes --show-labels | grep -o 'topology.kubernetes.io/zone=[^,[:space:]]*'