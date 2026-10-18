#!/usr/bin/env bash
# ⚠️ SPOILER: Reference fix for Scenario 01 (the scripted version of SOLUTION.md).
# Solve the scenario yourself first! CI uses this script to prove the scenario is solvable:
# break.sh -> verify.sh must FAIL -> fix.sh -> verify.sh must PASS.
# Run this script on k8s-worker (192.168.56.21)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

echo "🔧 Applying reference fix for Scenario 01 on $(hostname)..."

# Root cause: clientCAFile in the kubelet config points to a CA file that doesn't exist
sudo sed -i 's|/etc/kubernetes/pki/ca-missing.crt|/etc/kubernetes/pki/ca.crt|g' /var/lib/kubelet/config.yaml

sudo systemctl daemon-reload
sudo systemctl restart kubelet
