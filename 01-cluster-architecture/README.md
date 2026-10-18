# Domain 1: Cluster Architecture, Installation & Configuration (25% of CKA)

[⬅ Back to Main CKA Hub](../Readme.md)

This module covers **25% of the CKA exam**. Now that you have bootstrapped your 2-node `kubeadm` cluster (`k8s-master` and `k8s-worker`), work through these hands-on labs to master RBAC, cluster version upgrades, `etcd` backup/restore, and package management (Helm & Kustomize).

---

## Table of Contents
- [Lab 1.1: Role-Based Access Control (RBAC) & ServiceAccounts](#lab-11-role-based-access-control-rbac--serviceaccounts)
- [Lab 1.2: Upgrading a kubeadm Cluster (v1.29 → v1.30)](#lab-12-upgrading-a-kubeadm-cluster-v129--v130)
- [Lab 1.3: Backing Up and Restoring etcd](#lab-13-backing-up-and-restoring-etcd)
- [Lab 1.4: Kustomize & Helm Basics](#lab-14-kustomize--helm-basics)
- [Lab 1.5: Certificate Management (`kubeadm certs`) & CRDs](#lab-15-certificate-management-kubeadm-certs--crds)

---

## Lab 1.1: Role-Based Access Control (RBAC) & ServiceAccounts

### Exam Scenario
> Create a namespace named `audit`. In that namespace:
> 1. Create a `ServiceAccount` named `log-reader`.
> 2. Create a `Role` named `pod-log-role` that allows `get`, `list`, and `watch` on `pods` and `pods/log`.
> 3. Bind `pod-log-role` to the `log-reader` ServiceAccount using a `RoleBinding` named `read-pods-binding`.
> 4. Create a `ClusterRole` named `node-pv-viewer` that allows `get` and `list` on cluster-scoped `nodes` and `persistentvolumes`, and bind it to `log-reader` using a `ClusterRoleBinding` named `read-nodes-binding`.
> 5. Verify permissions using `kubectl auth can-i`.

### Step-by-Step Lab

1. **Create the namespace and ServiceAccount imperatively:**
   ```bash
   kubectl create namespace audit
   kubectl create serviceaccount log-reader -n audit
   ```

2. **Create the namespace-scoped Role and RoleBinding:**
   ```bash
   kubectl create role pod-log-role \
     --verb=get,list,watch \
     --resource=pods,pods/log \
     -n audit

   kubectl create rolebinding read-pods-binding \
     --role=pod-log-role \
     --serviceaccount=audit:log-reader \
     -n audit
   ```

3. **Create the cluster-scoped ClusterRole and ClusterRoleBinding:**
   ```bash
   kubectl create clusterrole node-pv-viewer \
     --verb=get,list \
     --resource=nodes,persistentvolumes

   kubectl create clusterrolebinding read-nodes-binding \
     --clusterrole=node-pv-viewer \
     --serviceaccount=audit:log-reader
   ```

4. **Verify with `kubectl auth can-i`:**
   ```bash
   # Should return "yes"
   kubectl auth can-i get pods -n audit --as=system:serviceaccount:audit:log-reader
   kubectl auth can-i get pods/log -n audit --as=system:serviceaccount:audit:log-reader
   kubectl auth can-i list nodes --as=system:serviceaccount:audit:log-reader

   # Should return "no" (cannot delete pods or read secrets)
   kubectl auth can-i delete pods -n audit --as=system:serviceaccount:audit:log-reader
   kubectl auth can-i get secrets -n audit --as=system:serviceaccount:audit:log-reader

   # Cleanup
   kubectl delete clusterrolebinding read-nodes-binding
   kubectl delete clusterrole node-pv-viewer
   kubectl delete namespace audit
   ```

> **💡 Exam Tip:** Remember the difference between `Role` (namespace-scoped) and `ClusterRole` (cluster-scoped). You can also bind a `ClusterRole` to a single namespace using a `RoleBinding`!

---

## Lab 1.2: Upgrading a `kubeadm` Cluster (`v1.29` → `v1.30`)

> **kind path:** ❌ VM-only. kind nodes are immutable images, so there is no apt repo to switch. To "upgrade" on kind, recreate the cluster with a newer `kindest/node` image. Practice this lab on [Path A](../Readme.md#choose-your-path-vms-or-kind).
>
> **⚠️ Snapshot First!** Take a VMware snapshot of `k8s-master` and `k8s-worker` before running this lab so you can practice the upgrade multiple times.
> **🔥 Want to practice a Zero-Downtime Live Upgrade with running workloads, a `PodDisruptionBudget`, and a live HTTP uptime monitor?** See [**Section 8 of the Main Guide (`Live Cluster Upgrade With Running Workloads`)**](../Readme.md#8-live-cluster-upgrade-v129--v130-with-running-workloads).

### Exam Scenario
> Upgrade the control plane node (`k8s-master`) and worker node (`k8s-worker`) from Kubernetes `v1.29.x` to `v1.30.x`. Ensure workloads are safely drained before maintenance and uncordoned afterward.

### Part A: Upgrade the Control Plane Node (`k8s-master`)

1. **Update the Kubernetes apt repository to `v1.30`:**
   ```bash
   curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
   sudo apt update
   ```

2. **Check available `1.30` versions and upgrade `kubeadm` first:**
   ```bash
   sudo apt-cache madison kubeadm
   # Replace 1.30.x-1.1 with the latest 1.30 patch version shown above (e.g., 1.30.5-1.1)
   sudo apt-mark unhold kubeadm
   sudo apt install -y kubeadm=1.30.5-1.1
   sudo apt-mark hold kubeadm
   ```

3. **Verify `kubeadm version`, check the upgrade plan, and apply the control-plane upgrade:**
   ```bash
   sudo kubeadm version
   sudo kubeadm upgrade plan
   sudo kubeadm upgrade apply v1.30.5 -y
   ```

4. **Drain the control plane node for `kubelet` maintenance:**
   ```bash
   kubectl drain k8s-master --ignore-daemonsets
   ```

5. **Upgrade `kubelet` and `kubectl` on `k8s-master`:**
   ```bash
   sudo apt-mark unhold kubelet kubectl
   sudo apt install -y kubelet=1.30.5-1.1 kubectl=1.30.5-1.1
   sudo apt-mark hold kubelet kubectl

   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   ```

6. **Uncordon the control plane node:**
   ```bash
   kubectl uncordon k8s-master
   ```

### Part B: Upgrade the Worker Node (`k8s-worker`)

1. **From `k8s-master`, drain `k8s-worker`:**
   *(Note: If you have live workloads protected by a `PodDisruptionBudget` on a 2-node cluster, temporarily untaint `k8s-master` first so evicted pods can schedule onto `k8s-master` during worker maintenance!)*
   ```bash
   kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule- || true
   kubectl drain k8s-worker --ignore-daemonsets --delete-emptydir-data
   ```

2. **SSH into `k8s-worker` (`ssh username@192.168.56.21`) and update the apt repo:**
   ```bash
   curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
   sudo apt update
   ```

3. **Upgrade `kubeadm` and run `kubeadm upgrade node` on `k8s-worker`:**
   ```bash
   sudo apt-mark unhold kubeadm
   sudo apt install -y kubeadm=1.30.5-1.1
   sudo apt-mark hold kubeadm

   # Note: On worker nodes (and secondary control plane nodes), use "kubeadm upgrade node" (NOT "upgrade apply")
   sudo kubeadm upgrade node
   ```

4. **Upgrade `kubelet` and `kubectl` on `k8s-worker`:**
   ```bash
   sudo apt-mark unhold kubelet kubectl
   sudo apt install -y kubelet=1.30.5-1.1 kubectl=1.30.5-1.1
   sudo apt-mark hold kubelet kubectl

   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   ```

5. **Back on `k8s-master`, uncordon `k8s-worker`, restore the control-plane taint, and verify:**
   ```bash
   kubectl uncordon k8s-worker
   kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule
   kubectl get nodes
   ```

---

## Lab 1.3: Backing Up and Restoring `etcd`

> **📚 Official Kubernetes Docs Note (`etcdctl` vs `etcdutl`):**
> - **`etcdctl snapshot save`** is used for taking **live online snapshots** from a running `etcd` endpoint (`https://127.0.0.1:2379`).
> - In modern `etcd` (`v3.5+`), offline snapshot operations (`snapshot status` and `snapshot restore`) have moved to **`etcdutl`**. A v3.5+ `etcdctl` still runs them, but prints a deprecation warning.
> - Ubuntu 22.04's `etcd-client` package is **etcd v3.3**: it has no `etcdutl`, and its `etcdctl` runs restore with no warning. Both commands are shown below so you are ready for either on the CKA exam!
>
> **kind path:** ⚠️ Steps 1–5 work by running `etcdctl` inside the etcd pod, which already has the certs mounted:
> `kubectl -n kube-system exec etcd-k8s-control-plane -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /var/lib/etcd/backup.db`
> The restore (steps 6–8) is VM-only. It means writing a new data directory on the node host and repointing the etcd static pod at it, which is the exam workflow the VM path reproduces.

### Exam Scenario
> 1. Take a snapshot of the `etcd` instance running on `k8s-master` and save it to `/opt/etcd-backup.db`.
> 2. Create a test pod (`kubectl run test-after-backup --image=nginx`).
> 3. Restore `etcd` from `/opt/etcd-backup.db` into a new data directory `/var/lib/etcd-restored` and configure the `etcd` static pod to use it. Verify that `test-after-backup` is gone!

### Step-by-Step Lab

1. **Install `etcd-client` on `k8s-master`:**
   ```bash
   sudo apt update && sudo apt install -y etcd-client
   ```

2. **Inspect `/etc/kubernetes/manifests/etcd.yaml` to find certificate paths:**
   ```bash
   sudo grep -E 'cert-file|key-file|trusted-ca-file|listen-client-urls' /etc/kubernetes/manifests/etcd.yaml
   ```

3. **Take the `etcd` snapshot (`etcdctl`):**
   ```bash
   sudo ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup.db \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/server.crt \
     --key=/etc/kubernetes/pki/etcd/server.key
   ```

4. **Verify the snapshot status:**
   ```bash
   # Using etcdutl (if installed on the exam node):
   sudo etcdutl snapshot status /opt/etcd-backup.db --write-out=table

   # Or using etcdctl (default on Ubuntu 22.04 etcd-client):
   sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-out=table
   ```

5. **Simulate cluster changes after the backup:**
   ```bash
   kubectl run test-after-backup --image=nginx
   kubectl get pods
   ```

6. **Restore the snapshot to a new host directory (`/var/lib/etcd-restored`):**
   ```bash
   # Using etcdutl (official etcd v3.5+ tool):
   sudo etcdutl snapshot restore /opt/etcd-backup.db --data-dir=/var/lib/etcd-restored

   # Or using etcdctl:
   sudo ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
     --data-dir=/var/lib/etcd-restored
   ```

7. **Update the `etcd` static pod manifest (`/etc/kubernetes/manifests/etcd.yaml`):**
   Edit `/etc/kubernetes/manifests/etcd.yaml` and change the `etcd-data` volume `hostPath` from `/var/lib/etcd` to `/var/lib/etcd-restored`:
   ```bash
   # The "$" anchor makes this safe to re-run (it won't produce etcd-restored-restored)
   sudo sed -i 's|path: /var/lib/etcd$|path: /var/lib/etcd-restored|' /etc/kubernetes/manifests/etcd.yaml
   ```

8. **Wait ~30–60 seconds for `kubelet` to recreate the `etcd` static pod and verify:**
   ```bash
   sudo crictl ps | grep etcd
   kubectl get pods
   # "test-after-backup" should no longer exist!
   ```

---

## Lab 1.4: Kustomize & Helm Basics

### Kustomize (Built into `kubectl -k`)

1. **Create a base deployment and a `kustomization.yaml` overlay:**
   ```bash
   mkdir -p ~/kustomize-lab && cd ~/kustomize-lab

   kubectl create deployment web --image=nginx:1.25 --dry-run=client -o yaml > deployment.yaml

   cat <<EOF > kustomization.yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   namePrefix: prod-
   labels:
     - pairs:
         env: production
   resources:
     - deployment.yaml
   replicas:
     - name: web
       count: 3
   EOF
   ```

2. **Preview and apply with `kubectl kustomize` / `kubectl apply -k`:**
   ```bash
   kubectl kustomize ~/kustomize-lab
   kubectl apply -k ~/kustomize-lab
   kubectl get deploy -l env=production
   kubectl delete -k ~/kustomize-lab
   ```

### Common Helm Exam Commands
```bash
# List repositories and update
helm repo list
helm repo update

# List installed Helm releases across all namespaces (including pending/failed)
helm list -A -a

# Upgrade a release with a custom parameter
helm upgrade <release-name> <repo>/<chart> -n <namespace> --set replicas=2

# Uninstall a release
helm uninstall <release-name> -n <namespace>
```

---

## Lab 1.5: Certificate Management (`kubeadm certs`) & CRDs

### Part A: Inspecting & Renewing Cluster Certificates
In `kubeadm` clusters, all PKI certificates live in `/etc/kubernetes/pki/`.

```bash
# 1. Check expiration dates of all Kubernetes control plane certificates
sudo kubeadm certs check-expiration

# 2. Inspect a specific certificate (e.g., apiserver.crt) using openssl
sudo openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A 2 "Validity"

# 3. Renew all certificates (or a specific one like 'kubeadm certs renew apiserver')
sudo kubeadm certs renew all
```

### Part B: Inspecting Custom Resource Definitions (CRDs)
Since your cluster uses Calico (and Prometheus if installed), you already have real CRDs to inspect:

```bash
# 1. List all CustomResourceDefinitions in the cluster
kubectl get crd

# 2. Inspect the schema of a Calico CRD using kubectl explain
kubectl explain installations.spec.calicoNetwork
```


---

⬅ **Previous:** [Cheatsheet](../cheatsheets/cka-exam-day-survival-guide.md) · [⬆ CKA Study Hub](../Readme.md#cka-study-hub--hands-on-lab-modules) · **Next:** [Domain 2: Workloads & Scheduling](../02-workloads-scheduling/README.md) ➡
