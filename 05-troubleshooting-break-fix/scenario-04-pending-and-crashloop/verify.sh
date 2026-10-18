#!/usr/bin/env bash
# Verification script for Scenario 04 (Run on k8s-master)

set -e

echo "🔍 Verifying Scenario 04..."

# 1. Check that nodeSelector was kept on the Deployment
NODE_SEL=$(kubectl get deploy order-processor -n cka-workload-lab -o jsonpath='{.spec.template.spec.nodeSelector.disktype}')
if [ "$NODE_SEL" != "nvme-ultra" ]; then
  echo "❌ FAIL: The nodeSelector 'disktype: nvme-ultra' was removed from the Deployment! Label the worker node instead."
  exit 1
fi

# 2. Check that livenessProbe port was fixed to 80
PROBE_PORT=$(kubectl get deploy order-processor -n cka-workload-lab -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.port}')
if [ "$PROBE_PORT" != "80" ]; then
  echo "❌ FAIL: The livenessProbe httpGet port is still '$PROBE_PORT' ( causing restarts )."
  exit 1
fi

# 3. Check Ready replicas
READY=$(kubectl get deploy order-processor -n cka-workload-lab -o jsonpath='{.status.readyReplicas}')
if [ "$READY" != "2" ]; then
  echo "❌ FAIL: Deployment 'order-processor' currently has '${READY:-0}/2' ready replicas. Wait a few seconds and try again."
  exit 1
fi

echo "✅ PASS! Both replicas of 'order-processor' are scheduled and 1/1 Ready!"
echo "   (Cleaning up namespace 'cka-workload-lab' and node label...)"
kubectl delete namespace cka-workload-lab --wait=false &>/dev/null || true
kubectl label nodes --all disktype- &>/dev/null || true
