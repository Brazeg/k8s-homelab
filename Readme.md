# Kubernetes Homelab & CKA Preparation Guide

[![Break-Fix Scenarios](https://github.com/Brazeg/k8s-homelab/actions/workflows/scenarios.yml/badge.svg)](./05-troubleshooting-break-fix/README.md#4-how-the-scenarios-test-themselves-ci)

A hands-on **CKA (Certified Kubernetes Administrator)** course on your own Windows 11 machine. You build a production-like 2-node **Vanilla Kubernetes (`kubeadm`)** cluster, then work through labs for every exam domain and break-fix scenarios that grade your fixes. No cloud bills.

<img src="Space Captain.png" alt="Lab Setup" title="Kubernetes Space Captain" width="800"/>

## How This Course Works

1. **Build your cluster.** [Choose a path](#choose-your-path-vms-or-kind): full Ubuntu VMs ([Path A](./vm/README.md), ~1–2 hours) or kind containers ([Path B](./kind/README.md), ~5 minutes).
2. **Work through the labs.** The [CKA Study Hub](#cka-study-hub--hands-on-lab-modules) has one module per exam domain, in the recommended order.
3. **Test yourself.** [Domain 05](./05-troubleshooting-break-fix/README.md) breaks your cluster on purpose, and a script grades your fix.

> **Looking for the VM setup steps** (VMware, `kubeadm init`, Calico, the live upgrade)? They moved to [**`vm/README.md`**](./vm/README.md).

---

## What You'll Learn

Instead of clicking through a managed service, you'll run the cluster the way a Kubernetes administrator does:

- Set up the container runtime (`containerd`), control plane (`kubeadm`), and CNI networking (`Calico`) yourself 🔧
- Debug nodes at the level the exam tests: `systemctl`, `journalctl`, `crictl`, static pod manifests 🩺
- Practice RBAC, scheduling, Services, Ingress and Gateway API, NetworkPolicy, storage, `etcd` backup, and cluster upgrades 📚
- Drive everything from your Windows terminal over SSH (Path A) or WSL (Path B) 💻

---

## Choose Your Path: VMs or kind

Both paths end with a 2-node `kubeadm` cluster running Calico, and both use the same CKA labs in this repo. Pick based on how much time you want to spend on infrastructure:

| | **Path A: Full VM Lab** | **Path B: kind Quick Start** |
| :--- | :--- | :--- |
| **What you build** | 2 Ubuntu VMs in VMware (`k8s-master`, `k8s-worker`) | 2 Docker-container nodes (`k8s-control-plane`, `k8s-worker`) via [kind](https://kind.sigs.k8s.io/) |
| **Setup time** | ~1–2 hours | ~5 minutes |
| **Host needs** | VMware Workstation Pro, 16GB RAM recommended | Docker Desktop (WSL2 backend), 8GB RAM |
| **CKA coverage** | 100%, including OS prep, `kubeadm init/join`, and cluster upgrades | ~85%: every workload, networking, storage, and RBAC lab, plus node-level break-fix via `docker exec`. No OS setup or `kubeadm` upgrades |
| **Start here** | [**`vm/README.md`**](./vm/README.md) | [**`kind/README.md`**](./kind/README.md) |

> **Not sure?** Start with Path B so you're practicing Kubernetes today, then build Path A before exam week to cover upgrades and node setup. kind is itself built on `kubeadm`, so the static pods, `kubelet` config, and `crictl` you see inside its nodes are the same as on the VMs.

---

## Understanding Kubernetes Distributions (Why `kubeadm` for CKA?)

When learning Kubernetes, it is easy to get confused by the different ways to run a cluster locally (`kind`, `minikube`, `MicroK8s`, `k3s`, or `kubeadm`). **Short version:** the CKA exam runs on `kubeadm` clusters, so this lab does too.

<details>
<summary><b>Read the full comparison</b></summary>

### What This Lab Uses
This repository builds **Vanilla (Upstream) Kubernetes using `kubeadm`**:
- **Bootstrap Tool:** `kubeadm` (official Kubernetes cluster lifecycle tool)
- **Container Runtime:** `containerd` (industry standard CRI runtime)
- **Container Network Interface (CNI):** Calico (supports `NetworkPolicy` out of the box)
- **Infrastructure:** 2 full Linux VMs (`k8s-master` and `k8s-worker`) on Ubuntu Server 22.04 LTS

### Comparison: `kubeadm` vs. `kind` vs. `Minikube` vs. `MicroK8s` / `k3s`

| Feature | **Vanilla K8s (`kubeadm`)** *(This Repo)* | **kind (K8s in Docker)** | **Minikube** | **MicroK8s / k3s** |
| :--- | :--- | :--- | :--- | :--- |
| **What is it?** | Official upstream Kubernetes bootstrapped on real Linux VMs or bare metal. | Runs Kubernetes "nodes" inside Docker containers on your host. | Local single-node (or multi-node) cluster wrapped in a convenience CLI. | Lightweight, opinionated K8s distributions for edge, IoT, and fast local dev. |
| **How Control Plane Runs** | Static Pods in `/etc/kubernetes/manifests/` managed by systemd `kubelet`. | Inside Docker containers (`docker exec` instead of real VM SSH). | Abstracted inside a dedicated VM or container driver. | Custom services (`snap.microk8s.daemon-*` or single `k3s.service` binary). |
| **Container Runtime** | Standard `containerd` (`/etc/containerd/config.toml`). | `containerd` nested inside Docker containers. | Docker, `containerd`, or CRI-O (managed automatically). | Bundled `containerd` in custom non-standard paths. |
| **Networking & CNI** | Real multi-NIC Linux networking + full CNI (Calico) with `NetworkPolicy`. | Docker bridge network + basic `kindnet` by default (no `NetworkPolicy` unless customized). | Managed by Minikube driver; addons enabled via `minikube addons`. | Bundled CNI (Calico/Flannel) enabled via wrapper commands. |
| **Setup Effort** | **High** (you configure swap, kernel modules, sysctl, CRI, CNI, and node joins). | **Very Low** (`kind create cluster` takes ~30 seconds). | **Low** (`minikube start`). | **Low** (`snap install microk8s` or `curl \| sh` for k3s). |
| **Best Use Case** | **CKA Exam Prep**, learning real cluster administration, production architecture. | Fast local application testing & CI/CD pipelines. | Beginners learning basic `kubectl` & YAML manifests. | Edge computing, Raspberry Pi homelabs, lightweight production. |
| **CKA Exam Readiness** | ⭐⭐⭐⭐⭐ **100% Match** | ⭐⭐⭐⭐ Nodes are `kubeadm`-built, so static pods, `kubelet`, and `crictl` work via `docker exec`. No OS prep or `kubeadm upgrade` practice ([Path B](./kind/README.md)) | ⭐⭐ Hides cluster internals | ⭐⭐ Different file paths and daemon names than the exam |

### Why `kubeadm` Is Essential Before Taking the CKA Exam
The official **CKA exam environment** runs on Ubuntu nodes provisioned with **`kubeadm`**, **`containerd`**, and **`systemd`**. By building this lab, you gain muscle memory for high-value CKA exam tasks that cannot be practiced properly on Minikube or MicroK8s:
1. **Cluster Bootstrapping & Node Joins:** Running `kubeadm init` and `kubeadm token create --print-join-command`.
2. **Cluster Upgrades:** Practicing `kubeadm upgrade plan` and `kubeadm upgrade apply` across control-plane and worker nodes.
3. **Control Plane & Static Pod Troubleshooting:** Inspecting `/etc/kubernetes/manifests/` (`kube-apiserver.yaml`, `etcd.yaml`, `kube-scheduler.yaml`, `kube-controller-manager.yaml`).
4. **Node & Runtime Debugging:** Fixing broken worker nodes using `systemctl status kubelet`, `journalctl -xeu kubelet`, `/etc/containerd/config.toml`, and `crictl`.
5. **Network Policies:** Using Calico to enforce ingress/egress `NetworkPolicy` rules between namespaces and pods.

</details>

---

## CKA Study Hub & Hands-On Lab Modules

Once your 2-node cluster is up and running ([Path A](./vm/README.md) or [Path B](./kind/README.md)), work through the **5 Official CKA Exam Domains** and interactive **Break & Fix** troubleshooting scenarios included in this repository. The **kind** column shows what works on Path B: ✅ as written, ⚠️ some labs need a small tweak or are VM-only (see the [kind compatibility matrix](./kind/README.md#4-lab-compatibility-matrix)).

| CKA Domain / Resource | Exam Weight | kind | Hands-On Labs Included |
| :--- | :---: | :---: | :--- |
| [**01. Cluster Architecture, Installation & Configuration**](./01-cluster-architecture/README.md) | **25%** | ⚠️ | RBAC (`Role`/`ClusterRole`/`ServiceAccount`), `kubeadm` Version Upgrade (`v1.29` → `v1.30`), `etcd` Snapshot Backup & Restore, Helm & Kustomize |
| [**02. Workloads & Scheduling**](./02-workloads-scheduling/README.md) | **15%** | ⚠️ | Rolling Updates & Rollbacks, Static Pods, DaemonSets, Taints & Tolerations, Node Affinity, Probes, Sidecar Pods, `metrics-server` (`kubectl top`) |
| [**03. Services & Networking**](./03-services-networking/README.md) | **20%** | ✅ | `ClusterIP`/`NodePort` & CoreDNS FQDN resolution, NGINX Ingress, **Gateway API** (`Gateway`/`HTTPRoute`), Calico `NetworkPolicy` |
| [**04. Storage**](./04-storage/README.md) | **10%** | ✅ | Static `PV` & `PVC` binding, Pod volume mounts, Dynamic Provisioning (`StorageClass` with Rancher `local-path-provisioner`) |
| [**05. Troubleshooting & Interactive Break-Fix Scenarios**](./05-troubleshooting-break-fix/README.md) | **30%** | ⚠️ | Visual Troubleshooting Flowchart + **4 Automated `break.sh` / `verify.sh` Exam Simulators** (`NotReady` Worker, Down API Server, NetworkPolicy Blackhole, `Pending`/`CrashLoopBackOff`) |
| [**⚡ CKA Exam Day Survival Guide & Cheatsheet**](./cheatsheets/cka-exam-day-survival-guide.md) | *Speed Boost* | ✅ | First-60-seconds `.bashrc`/`.vimrc` setup, Imperative `kubectl` generators, `jsonpath` one-liners, and `crictl`/`journalctl` node debugging |

**Recommended order:** start with the **cheatsheet** so the `k` alias and `$do` shortcuts are set up before you begin. Then work through Domains **01 → 05**. Domain 05 comes last on purpose: it mixes everything from the earlier domains. Each module ends with a link to the next one.

When a lab starts with an **Exam Scenario**, try to solve it on your own first, using `kubectl explain` and the [official docs](https://kubernetes.io/docs/) (the exam allows them), and only then open **Show solution**.

> **Stuck on setup?** See [Common Setup Problems & Fixes](./Common%20problems/Readme.md).
