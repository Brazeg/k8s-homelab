#!/usr/bin/env bash
# CKA Break-Fix Scenario 01: Worker Node NotReady
# Run this script on k8s-worker (192.168.56.21)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

echo "🔧 Injecting Scenario 01 failure on $(hostname)..."

if [ ! -f /var/lib/kubelet/config.yaml ]; then
  echo "❌ Error: /var/lib/kubelet/config.yaml not found. Make sure you run this on a kubeadm node."
  exit 1
fi

# Backup original config
sudo cp /var/lib/kubelet/config.yaml /var/lib/kubelet/config.yaml.bak

# Introduce a subtle typo in the clientCAFile path inside /var/lib/kubelet/config.yaml
sudo sed -i 's|/etc/kubernetes/pki/ca.crt|/etc/kubernetes/pki/ca-missing.crt|g' /var/lib/kubelet/config.yaml

# Stop and restart kubelet so it crashes on startup
sudo systemctl restart kubelet || true

echo ""
echo "=================================================================="
echo "🚨 SCENARIO 01 ACTIVE: Worker Node NotReady"
echo "=================================================================="
echo "Task:"
echo "  The worker node ($(hostname)) is reporting NotReady (or will within 40s)."
echo "  Investigate why kubelet is failing on this node, fix the root cause,"
echo "  and ensure the node returns to the Ready state."
echo ""
echo "When finished, run: ./verify.sh"
echo "=================================================================="
