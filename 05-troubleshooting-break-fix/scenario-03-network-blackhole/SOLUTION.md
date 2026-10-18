# Scenario 03 Solution: Service & NetworkPolicy Blackhole

[⬅ Back to Troubleshooting Hub](../README.md)

## Exam Prompt
> In namespace `cka-net-lab`, the pod `frontend-client` cannot reach `http://payment-svc:80` (which should route to pod `payment-backend`). Fix all service and networking issues without deleting the `backend-lockdown` NetworkPolicy.

---

## Step-by-Step Diagnosis & Fix

1. **Check the Service and its Endpoints in `cka-net-lab`:**
   ```bash
   kubectl get svc,ep -n cka-net-lab
   ```
   Notice that `ENDPOINTS` for `payment-svc` is `<none>`!

2. **Compare the Service selector with the Pod labels:**
   ```bash
   kubectl describe svc payment-svc -n cka-net-lab | grep Selector
   kubectl get pods -n cka-net-lab --show-labels
   ```
   - `payment-svc` selector: `app=payment-service,tier=backend`
   - `payment-backend` labels: `app=payment-api,tier=backend`

3. **Fix the Service selector:**
   ```bash
   kubectl patch svc payment-svc -n cka-net-lab \
     -p '{"spec":{"selector":{"app":"payment-api"}}}'
   kubectl get ep payment-svc -n cka-net-lab
   ```

4. **Test connectivity again—why does it still time out?**
   ```bash
   kubectl exec -n cka-net-lab frontend-client -- wget -qO- --timeout=3 http://payment-svc:80
   ```
   Check for `NetworkPolicy` resources in `cka-net-lab`:
   ```bash
   kubectl get netpol -n cka-net-lab
   kubectl describe netpol backend-lockdown -n cka-net-lab
   ```
   `backend-lockdown` only allows ingress from pods matching `tier: wrong-frontend-label`, whereas `frontend-client` has label `tier: frontend`.

5. **Fix the `NetworkPolicy` ingress `podSelector`:**
   ```bash
   kubectl patch netpol backend-lockdown -n cka-net-lab --type='json' \
     -p='[{"op": "replace", "path": "/spec/ingress/0/from/0/podSelector/matchLabels/tier", "value": "frontend"}]'
   ```
   *(Or edit interactively with `kubectl edit netpol backend-lockdown -n cka-net-lab`).*

6. **Verify your fix:**
   ```bash
   ./verify.sh
   ```
