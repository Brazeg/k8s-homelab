#!/usr/bin/env bash
# Verification script for Scenario 03 (Run on k8s-master)

set -e

echo "🔍 Verifying Scenario 03..."

# 1. Ensure NetworkPolicy wasn't simply deleted
if ! kubectl get networkpolicy backend-lockdown -n cka-net-lab &>/dev/null; then
  echo "❌ FAIL: NetworkPolicy 'backend-lockdown' was deleted! You must fix the policy/labels, not delete it."
  exit 1
fi

# 2. Check Service Endpoints
# EndpointSlices instead of the v1 Endpoints API (deprecated in 1.33+, prints a warning)
EP=$(kubectl get endpointslices -n cka-net-lab -l kubernetes.io/service-name=payment-svc -o jsonpath='{.items[*].endpoints[*].addresses[*]}')
if [ -z "$EP" ]; then
  echo "❌ FAIL: Service 'payment-svc' still has no Endpoints!"
  echo "   Hint: Compare 'kubectl get pod payment-backend -n cka-net-lab --show-labels' with 'kubectl describe svc payment-svc -n cka-net-lab'."
  exit 1
fi

# 3. Test HTTP connectivity from frontend-client to payment-svc
if ! kubectl exec -n cka-net-lab frontend-client -- wget -qO- --timeout=3 http://payment-svc:80 &>/dev/null; then
  echo "❌ FAIL: 'frontend-client' still times out when connecting to http://payment-svc:80."
  echo "   Hint: Inspect 'kubectl describe netpol backend-lockdown -n cka-net-lab'."
  exit 1
fi

echo "✅ PASS! Service 'payment-svc' has active Endpoints and 'frontend-client' can reach 'payment-backend' through the NetworkPolicy!"
echo "   (Cleaning up namespace 'cka-net-lab'...)"
kubectl delete namespace cka-net-lab --wait=false &>/dev/null || true
