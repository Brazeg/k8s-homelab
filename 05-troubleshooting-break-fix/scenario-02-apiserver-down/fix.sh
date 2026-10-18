#!/usr/bin/env bash
# ⚠️ SPOILER: Reference fix for Scenario 02 (the scripted version of SOLUTION.md).
# Solve the scenario yourself first! CI uses this script to prove the scenario is solvable:
# break.sh -> verify.sh must FAIL -> fix.sh -> verify.sh must PASS.
# Run this script on k8s-master (192.168.56.20)

set -e
command -v sudo >/dev/null || sudo() { "$@"; }  # kind nodes run as root without sudo

echo "🔧 Applying reference fix for Scenario 02 on $(hostname)..."

# Root cause: kube-apiserver dials etcd on 2389, but etcd's client port is 2379.
# kubelet watches /etc/kubernetes/manifests and recreates the static pod on its own (~20s).
sudo sed -i 's|--etcd-servers=https://127.0.0.1:2389|--etcd-servers=https://127.0.0.1:2379|g' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
