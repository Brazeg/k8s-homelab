# Scenario 04 Solution: Stuck Workloads (`Pending` & `CrashLoopBackOff`)

[⬅ Back to Troubleshooting Hub](../README.md)

## Exam Prompt
> In namespace `cka-workload-lab`, the Deployment `order-processor` has `0/2` Ready pods. Without removing the `nodeSelector` from the Deployment, resolve both the scheduling issue and the container health check issue so all replicas stay `1/1 Running`.

---

## Step-by-Step Diagnosis & Fix

1. **Check the pod status in `cka-workload-lab`:**
   ```bash
   kubectl get pods -n cka-workload-lab
   ```
   Both pods are stuck in `Pending`.

2. **Describe one of the `Pending` pods to see the scheduler event:**
   ```bash
   kubectl describe pod -n cka-workload-lab -l app=order-processor
   ```
   Look at the `Events` section:
   ```text
   Warning  FailedScheduling  0/2 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 1 node(s) didn't match Pod's node affinity/selector.
   ```
   And inspect the `Node-Selectors` field: `disktype=nvme-ultra`.

3. **Label `k8s-worker` with `disktype=nvme-ultra`:**
   ```bash
   kubectl label node k8s-worker disktype=nvme-ultra
   ```

4. **Watch the pods—why do they start restarting (`CrashLoopBackOff`) after 6 seconds?**
   ```bash
   kubectl get pods -n cka-workload-lab -w
   kubectl describe pod -n cka-workload-lab -l app=order-processor
   ```
   Look at the `Events` section:
   ```text
   Warning  Unhealthy  Liveness probe failed: Get "http://172.16.x.x:8080/": dial tcp 172.16.x.x:8080: connect: connection refused
   Normal   Killing    Container nginx failed liveness probe, will be restarted
   ```
   The `nginx:alpine` container listens on port `80`, not `8080`!

5. **Fix the `livenessProbe` port in the Deployment:**
   ```bash
   kubectl edit deploy order-processor -n cka-workload-lab
   ```
   Change `livenessProbe.httpGet.port: 8080` to `port: 80` (or patch it directly):
   ```bash
   kubectl patch deploy order-processor -n cka-workload-lab --type='json' \
     -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/port", "value": 80}]'
   ```

6. **Verify the rollout and run the grader:**
   ```bash
   kubectl rollout status deploy/order-processor -n cka-workload-lab
   ./verify.sh
   ```
