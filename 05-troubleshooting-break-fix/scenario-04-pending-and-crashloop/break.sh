#!/usr/bin/env bash
# CKA Break-Fix Scenario 04: Stuck Workloads (Pending & CrashLoopBackOff)
# Run this script on k8s-master

set -e

echo "🔧 Setting up Scenario 04 in namespace 'cka-workload-lab'..."

kubectl delete namespace cka-workload-lab --ignore-not-found=true &>/dev/null || true
kubectl create namespace cka-workload-lab

# 1. Create a Deployment with an impossible nodeSelector + failing livenessProbe port
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-processor
  namespace: cka-workload-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: order-processor
  template:
    metadata:
      labels:
        app: order-processor
    spec:
      nodeSelector:
        disktype: nvme-ultra
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 2
          periodSeconds: 3
          failureThreshold: 2
EOF

echo ""
echo "=================================================================="
echo "🚨 SCENARIO 04 ACTIVE: Stuck Workloads (Pending & CrashLoopBackOff)"
echo "=================================================================="
echo "Task:"
echo "  In namespace 'cka-workload-lab', the Deployment 'order-processor'"
echo "  has 0/2 Ready pods. Diagnose all scheduling and container health"
echo "  issues so that both replicas reach 1/1 Running & Ready."
echo "  (Note: Do NOT remove the nodeSelector from the Deployment—instead,"
echo "   label 'k8s-worker' appropriately AND fix any container probe issues!)"
echo ""
echo "When finished, run: ./verify.sh"
echo "=================================================================="
