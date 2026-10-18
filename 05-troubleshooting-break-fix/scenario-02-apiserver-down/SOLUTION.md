# Scenario 02 Solution: Control Plane API Server Down

[⬅ Back to Troubleshooting Hub](../README.md)

## Exam Prompt
> Running `kubectl get nodes` on `k8s-master` fails with:
> `The connection to the server 192.168.56.20:6443 was refused - did you specify the right host or port?`
> Diagnose the control plane failure and restore the API server.

---

## Step-by-Step Diagnosis & Fix

1. **Since `kubectl` cannot reach `kube-apiserver`, use `crictl` to inspect containers at the runtime level:**
   ```bash
   sudo crictl ps -a | grep kube-apiserver
   ```
   You will see the `kube-apiserver` container in an `Exited` state!

2. **Check the container logs using `crictl logs` (or `/var/log/pods/`):**
   ```bash
   CONTAINER_ID=$(sudo crictl ps -a --name kube-apiserver -q | head -n 1)
   sudo crictl logs $CONTAINER_ID | tail -n 25
   ```
   Look at the error in the logs:
   ```text
   connection error: desc = "transport: Error while dialing: dial tcp 127.0.0.1:2389: connect: connection refused"
   ```
   `etcd` listens on client port **`2379`** (and peer port `2380`), NOT `2389`!

3. **Fix `/etc/kubernetes/manifests/kube-apiserver.yaml`:**
   ```bash
   sudo nano /etc/kubernetes/manifests/kube-apiserver.yaml
   ```
   Change:
   ```yaml
   - --etcd-servers=https://127.0.0.1:2389
   ```
   Back to:
   ```yaml
   - --etcd-servers=https://127.0.0.1:2379
   ```

4. **Wait 15–30 seconds for `kubelet` to detect the file change and recreate the static pod, then verify:**
   ```bash
   kubectl get nodes
   ./verify.sh
   ```

> **⚠️ Critical CKA Exam Trap:** Never save backup files (like `kube-apiserver.yaml.bak`) inside `/etc/kubernetes/manifests/`! `kubelet` tries to run **every** file in `/etc/kubernetes/manifests/` as a static pod, which will create duplicate conflicting control plane pods. Always put backups in `/root/` or `~/`.
