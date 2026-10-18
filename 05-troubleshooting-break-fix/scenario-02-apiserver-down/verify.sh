#!/usr/bin/env bash
# Verification script for Scenario 02 (Run on k8s-master)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

echo "🔍 Verifying Scenario 02..."

if ! kubectl get nodes &>/dev/null; then
  echo "❌ FAIL: 'kubectl get nodes' is still failing."
  echo "   Hint: Use 'sudo crictl ps -a | grep kube-apiserver' and 'sudo crictl logs <id>'."
  echo "   Wait 15-30 seconds if you just edited /etc/kubernetes/manifests/kube-apiserver.yaml."
  exit 1
fi

sudo rm -f /root/kube-apiserver.yaml.bak

echo "✅ PASS! The Kubernetes API Server is healthy and responding to kubectl!"
kubectl get nodes
