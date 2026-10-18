#!/usr/bin/env bash
# ⚠️ SPOILER: Reference fix for Scenario 03 (the scripted version of SOLUTION.md).
# Solve the scenario yourself first! CI uses this script to prove the scenario is solvable:
# break.sh -> verify.sh must FAIL -> fix.sh -> verify.sh must PASS.
# Run this script on k8s-master

set -e

echo "🔧 Applying reference fix for Scenario 03..."

# Root cause 1: the Service selector (app=payment-service) matches no pod, so it has no Endpoints
kubectl patch svc payment-svc -n cka-net-lab \
  -p '{"spec":{"selector":{"app":"payment-api"}}}'

# Root cause 2: the NetworkPolicy only allows ingress from tier=wrong-frontend-label
kubectl patch netpol backend-lockdown -n cka-net-lab --type='json' \
  -p='[{"op": "replace", "path": "/spec/ingress/0/from/0/podSelector/matchLabels/tier", "value": "frontend"}]'
