#!/usr/bin/env bash
# ⚠️ SPOILER: Reference fix for Scenario 04 (the scripted version of SOLUTION.md).
# Solve the scenario yourself first! CI uses this script to prove the scenario is solvable:
# break.sh -> verify.sh must FAIL -> fix.sh -> verify.sh must PASS.
# Run this script on k8s-master

set -e

echo "🔧 Applying reference fix for Scenario 04..."

# Root cause 1 (Pending): no node carries the label the nodeSelector asks for
kubectl label node k8s-worker disktype=nvme-ultra --overwrite

# Root cause 2 (CrashLoopBackOff): the livenessProbe checks 8080, but nginx listens on 80
kubectl patch deploy order-processor -n cka-workload-lab --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80}]'
