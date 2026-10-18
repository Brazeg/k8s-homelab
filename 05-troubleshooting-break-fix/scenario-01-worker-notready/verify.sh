#!/usr/bin/env bash
# Verification script for Scenario 01 (Run on k8s-worker)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

echo "🔍 Verifying Scenario 01..."

# 1. Check if kubelet service is active
if ! systemctl is-active --quiet kubelet; then
  echo "❌ FAIL: kubelet service is not running (status: $(systemctl is-active kubelet))."
  echo "   Hint: Check 'sudo systemctl status kubelet' and 'sudo journalctl -xeu kubelet'."
  exit 1
fi

# 2. Check if clientCAFile points to the valid /etc/kubernetes/pki/ca.crt
if grep -q "ca-missing.crt" /var/lib/kubelet/config.yaml; then
  echo "❌ FAIL: /var/lib/kubelet/config.yaml still contains an invalid CA certificate path."
  exit 1
fi

sudo rm -f /var/lib/kubelet/config.yaml.bak

echo "✅ PASS! kubelet is active and configured properly on $(hostname)."
echo "   Run 'kubectl get nodes' on k8s-master to confirm Ready status."
