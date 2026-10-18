#!/usr/bin/env bash
# CKA Break-Fix Scenario 02: Control Plane API Server Down
# Run this script on k8s-master (192.168.56.20)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"

if [ ! -f "$MANIFEST" ]; then
  echo "❌ Error: $MANIFEST not found. Run this script on the control-plane node (k8s-master)."
  exit 1
fi

echo "🔧 Injecting Scenario 02 failure on $(hostname)..."

# Backup original manifest outside /etc/kubernetes/manifests (never put backups inside manifests/!)
sudo cp "$MANIFEST" /root/kube-apiserver.yaml.bak

# Corrupt the etcd port in kube-apiserver.yaml (2379 -> 2389)
sudo sed -i 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:2389|g' "$MANIFEST"

sleep 5

echo ""
echo "=================================================================="
echo "🚨 SCENARIO 02 ACTIVE: Control Plane API Server Down"
echo "=================================================================="
echo "Task:"
echo "  Running 'kubectl get nodes' now fails with a connection error!"
echo "  Investigate why the Kubernetes API server is not responding on"
echo "  k8s-master and restore control plane functionality."
echo ""
echo "When finished, run: ./verify.sh"
echo "=================================================================="
