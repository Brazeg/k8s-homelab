# Path B: kind Quick Start (Kubernetes Core Labs Without VMs)

[⬅ Back to Main Guide](../Readme.md#choose-your-path-vms-or-kind)

This path skips VMware and Ubuntu installs. In ~5 minutes you get a **2-node `kubeadm` cluster with `containerd` and Calico**, running as Docker containers on your Windows machine through [kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker). You can then go straight to the [CKA domain labs](../Readme.md#cka-study-hub--hands-on-lab-modules).

**Why kind (and not Minikube, MicroK8s or k3s)?** kind builds every node with `kubeadm`, the same tool the CKA exam environment uses. Inside a kind node you'll find the same `/etc/kubernetes/manifests` static pods, `/var/lib/kubelet/config.yaml`, `systemctl status kubelet`, `journalctl`, and `crictl` as on the VMs, so even the node-level break-fix scenarios work. k3s and MicroK8s use different binaries and file paths, and Minikube hides the nodes behind its own CLI.

---

## Table of Contents
- [1. Prerequisites (Windows 11 + WSL2)](#1-prerequisites-windows-11--wsl2)
- [2. Create the Cluster](#2-create-the-cluster)
- [3. VM Path → kind Path Translation](#3-vm-path--kind-path-translation)
- [4. Lab Compatibility Matrix](#4-lab-compatibility-matrix)
- [5. Monitoring Stack on kind](#5-monitoring-stack-on-kind)
- [6. Reset, Delete & Moving to Path A](#6-reset-delete--moving-to-path-a)

---

## 1. Prerequisites (Windows 11 + WSL2)

The labs are written for a **bash** shell (heredocs, `chmod`, `.sh` scripts), so run everything from an **Ubuntu terminal in WSL2**, not PowerShell.

1. **Install WSL2 with Ubuntu** (PowerShell as Administrator, then reboot):
   ```powershell
   wsl --install -d Ubuntu
   ```
2. **Install [Docker Desktop](https://www.docker.com/products/docker-desktop/)** and enable:
   - *Settings → General → Use the WSL 2 based engine*
   - *Settings → Resources → WSL integration → Ubuntu*

   Give Docker at least **4 CPUs / 6GB RAM** if you plan to run the monitoring stack.
3. **Inside the WSL Ubuntu terminal**, install `kind` and `kubectl` (pinned versions that match `kind-config.yaml`):
   ```bash
   # kind v0.33.0
   curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.33.0/kind-linux-amd64
   sudo install -m 0755 kind /usr/local/bin/kind && rm kind

   # kubectl v1.35.8 (matches the node image)
   curl -LO https://dl.k8s.io/release/v1.35.8/bin/linux/amd64/kubectl
   sudo install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

   docker version && kind version && kubectl version --client
   ```
   For Helm, use the same commands as [Main Guide Section 7.1](../Readme.md#71-install-helm).
4. **Optional:** install [Task](https://taskfile.dev) for the shortcuts in [`Taskfile.yml`](../Taskfile.yml):
   ```bash
   sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin
   task   # lists every shortcut
   ```

---

## 2. Create the Cluster

```bash
git clone https://github.com/Brazeg/k8s-homelab.git
cd k8s-homelab

# 1. Create the 2-node cluster (k8s-control-plane + k8s-worker), no default CNI
kind create cluster --config kind/kind-config.yaml

# 2. Install Calico: CRDs, then the operator, then the default Installation (pod CIDR 192.168.0.0/16)
#    (In recent Calico releases the CRDs are a separate manifest; tigera-operator.yaml no longer includes them)
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/v1_crd_projectcalico_org.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.2/manifests/custom-resources.yaml

# 3. Wait for both nodes to become Ready (Calico takes 1–3 minutes)
kubectl wait --for=condition=Ready nodes --all --timeout=300s
kubectl wait --for=condition=Available tigerastatus --all --timeout=300s       # Calico's own health report
kubectl wait --for=condition=Available deployment --all -n kube-system --timeout=300s   # CoreDNS
kubectl get nodes -o wide
kubectl get pods -A
```

The nodes stay `NotReady` until Calico is running. That's expected, and it's the same CNI lesson as on the VMs.

Why not just `kubectl wait pods --all -A`? While the Calico operator rolls out, it replaces some pods. If a pod `kubectl wait` is watching gets deleted, the wait fails with `NotFound`. Pods are disposable, so wait on what owns them instead: the `TigeraStatus` objects (the operator's summary of each Calico component) and the CoreDNS `Deployment`.

> **Shortcut:** `task kind:up` runs steps 1–3 for you. Type the commands by hand at least once first, so you know what the shortcut does.

---

## 3. VM Path → kind Path Translation

Whenever a lab says the left column, do the right column:

| VM Path (Path A) | kind Path (Path B) |
| :--- | :--- |
| Node `k8s-master` | Node `k8s-control-plane` |
| Node `k8s-worker` | Node `k8s-worker` *(same name)* |
| `ssh username@192.168.56.20` | `docker exec -it k8s-control-plane bash` |
| `ssh username@192.168.56.21` | `docker exec -it k8s-worker bash` |
| `sudo <cmd>` on a node | Just `<cmd>`: you are already `root` inside the node container |
| `http://192.168.56.20:<NodePort>` | `http://localhost:<NodePort>` (only 30080, 30081, 30300 and 30909 are mapped, see [`kind-config.yaml`](./kind-config.yaml)) |
| Pod IPs `172.16.x.x` | Pod IPs `192.168.x.x` |
| VMware snapshot / revert | `kind delete cluster --name k8s` + `kind create cluster ...` (section 6) |

---

## 4. Lab Compatibility Matrix

✅ works as written · ⚠️ works with the tweak shown · ❌ VM-only

| Lab | kind | Notes |
| :--- | :---: | :--- |
| **1.1** RBAC & ServiceAccounts | ✅ | |
| **1.2** `kubeadm` upgrade | ❌ | kind nodes are immutable images; there is no apt repo to switch. Use Path A |
| **1.3** `etcd` backup & restore | ⚠️ | Backup works via `kubectl exec` into the etcd pod (callout in the lab). Restore is VM-only |
| **1.4** Kustomize & Helm | ✅ | |
| **1.5** Certs & CRDs | ⚠️ | Run inside the node: `docker exec k8s-control-plane kubeadm certs check-expiration` |
| **2.1** Rolling updates | ✅ | |
| **2.2** Static pods & DaemonSets | ⚠️ | Write the manifest with `docker exec -i k8s-control-plane tee ...` (callout in the lab) |
| **2.3** Taints & affinity | ✅ | Targets `k8s-worker`, which exists on kind too |
| **2.4** ConfigMaps, Secrets, probes, sidecars | ✅ | |
| **2.5** `metrics-server` & HPA | ✅ | The `--kubelet-insecure-tls` patch is needed on kind as well |
| **3.1** Services & CoreDNS | ✅ | |
| **3.2** Ingress | ⚠️ | Use manifest `controller-v1.15.1` (Kubernetes 1.35) and `curl http://localhost:30081/...` |
| **3.3** Gateway API | ✅ | |
| **3.4** NetworkPolicy (Calico) | ✅ | |
| **4.1** Static PV/PVC | ✅ | `hostPath` lives inside the node container |
| **4.2** Dynamic provisioning | ⚠️ | kind **already runs** `local-path-provisioner` with a default StorageClass named `standard`. Skip steps 1–2 and run step 3 as-is |
| **4.3** PVC expansion | ⚠️ | Patch `standard` instead of `local-path`. Same "no resizer" result as on the VMs |
| **5** Scenarios 03 & 04 | ✅ | Run from WSL |
| **5** Scenarios 01 & 02 | ⚠️ | Run inside the node via `docker cp` + `docker exec` ([how](../05-troubleshooting-break-fix/README.md#3-how-to-run-a-scenario)) |
| **Main Guide §7** Monitoring | ✅ | Use `localhost` instead of `192.168.56.20` (troubleshooting note in section 5 below) |
| **Main Guide §8** Live upgrade | ❌ | Path A only |
| **Cheatsheet** | ✅ | Node commands (`crictl`, `journalctl`) work inside `docker exec` |

---

## 5. Monitoring Stack on kind

[Main Guide Section 7.2](../Readme.md#72-install-prometheus-and-grafana) works as written. If the `monitoring-prometheus-node-exporter-*` pods fail to start with `path / is mounted on / but it is not a shared or slave mount` (a known Docker Desktop mount-propagation issue), turn off the host root mount:

```bash
helm upgrade monitoring prometheus-community/kube-prometheus-stack -n monitoring \
  --reuse-values --set prometheus-node-exporter.hostRootFsMount.enabled=false
```

Access Grafana either way:
- `kubectl port-forward deployment/monitoring-grafana 3000 -n monitoring` → `http://localhost:3000`, or
- apply the NodePort manifest from [Section 7.4](../Readme.md#74-optional-access-grafana-and-prometheus-using-nodeport) → `http://localhost:30300` (Grafana) and `http://localhost:30909` (Prometheus).

---

## 6. Reset, Delete & Moving to Path A

```bash
# Instant "snapshot revert": throw the cluster away and rebuild it
kind delete cluster --name k8s
kind create cluster --config kind/kind-config.yaml   # then re-run the Calico steps in section 2
# ...or all of the above in one go: task kind:reset

# Pause the cluster to free CPU/RAM (state is kept on disk)
docker stop k8s-control-plane k8s-worker
docker start k8s-control-plane k8s-worker
```

> **Restart caveat:** Docker can give the nodes different IPs when they restart (for example after a reboot). If a node stays `NotReady` or `calico-node` crash-loops afterwards, run `kubectl delete pod -n calico-system -l k8s-app=calico-node`. If that doesn't fix it, recreate the cluster.

**Before exam day**, build [Path A](../Readme.md#1-infrastructure-setup) at least once. It is the only way to practice what kind can't cover: OS prep (swap, kernel modules, `sysctl`), `kubeadm init/join`, `kubeadm upgrade` across versions (Lab 1.2 and Section 8), and a full `etcd` restore.
