#!/usr/bin/env bash
# CKA Break-Fix Scenario 03: Service & NetworkPolicy Blackhole
# Run this script on k8s-master

set -e

echo "🔧 Setting up Scenario 03 in namespace 'cka-net-lab'..."

kubectl delete namespace cka-net-lab --ignore-not-found=true &>/dev/null || true
kubectl create namespace cka-net-lab

# kube-controller-manager creates the namespace's 'default' ServiceAccount a moment later.
# Creating a bare pod before that is rejected ("serviceaccount default not found").
for _ in $(seq 1 60); do
  kubectl get serviceaccount default -n cka-net-lab &>/dev/null && break
  sleep 1
done

# 1. Create backend pod with label app=payment-api,tier=backend
kubectl run payment-backend -n cka-net-lab \
  --image=nginx:alpine \
  --labels="app=payment-api,tier=backend" \
  --port=80

# 2. Create frontend client pod
kubectl run frontend-client -n cka-net-lab \
  --image=busybox:1.36 \
  --labels="app=checkout,tier=frontend" \
  -- sleep 3600

# 3. Create Service with a subtle selector typo (app=payment-service instead of app=payment-api)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: payment-svc
  namespace: cka-net-lab
spec:
  selector:
    app: payment-service
    tier: backend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF

# 4. Apply a restrictive NetworkPolicy that blocks ingress to tier=backend unless pod has role=allowed
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-lockdown
  namespace: cka-net-lab
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: wrong-frontend-label
    ports:
    - protocol: TCP
      port: 80
EOF

kubectl wait --for=condition=ready pod --all -n cka-net-lab --timeout=60s

echo ""
echo "=================================================================="
echo "🚨 SCENARIO 03 ACTIVE: Service & NetworkPolicy Blackhole"
echo "=================================================================="
echo "Task:"
echo "  In namespace 'cka-net-lab', the pod 'frontend-client' cannot reach"
echo "  http://payment-svc:80 (which should route to pod 'payment-backend')."
echo "  Fix all networking/service issues in 'cka-net-lab' WITHOUT deleting"
echo "  the NetworkPolicy 'backend-lockdown'."
echo ""
echo "When finished, run: ./verify.sh"
echo "=================================================================="
