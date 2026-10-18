# Path A: Full VM Lab (kubeadm on VMware Workstation)

[⬅ Back to Main CKA Hub](../Readme.md) · On Path B? Use the [kind Quick Start](../kind/README.md) instead.

Build a 2-node **Vanilla Kubernetes** cluster (`k8s-master` + `k8s-worker`) on Ubuntu Server VMs, from OS prep to `kubeadm init`, Calico, and joining the worker. Budget **1–2 hours**. Sections 1–6 are the core setup; 7 and 8 are optional extras.

## Table of Contents
- [Prerequisites](#prerequisites-for-kubernetes-lab-environment)
- [1. Infrastructure Setup](#1-infrastructure-setup)
- [2. Basic System Configuration](#2-basic-system-configuration)
- [3. Kubernetes Installation](#3-kubernetes-installation)
- [4. Initialize Kubernetes Cluster](#4-initialize-kubernetes-cluster)
- [5. Join Worker Node to Cluster](#5-join-worker-node-to-cluster)
- [6. Verify Cluster Setup](#6-verify-cluster-setup)
- [7. Install Monitoring Stack (Prometheus and Grafana)](#7-install-monitoring-stack-prometheus-and-grafana) *(optional)*
- [8. Live Cluster Upgrade With Running Workloads](#8-live-cluster-upgrade-v129--v130-with-running-workloads) *(optional, do it after Lab 1.2)*
- [9. Troubleshooting and Verification](#9-troubleshooting-and-verification) · [Common Setup Problems & Fixes](../Common%20problems/Readme.md)
- [10. Accessing Kubernetes Cluster from Windows Host Machine](#10-accessing-kubernetes-cluster-from-windows-host-machine)
- [11. Next Steps](#11-next-steps)

---

## Prerequisites for Kubernetes Lab Environment

### 1. Hardware Requirements

**Host Computer Specifications:**
- **CPU:** Intel/AMD processor with virtualization support enabled in BIOS (VT-x / AMD-V)
- **RAM:** Minimum 8GB (16GB recommended)
- **Storage:** At least 40GB free disk space
- **Operating System:** Windows 11

### 2. Software Requirements

#### 2.1 VMware Workstation Pro (17 / 25H2 / 26H1u1+ — Free)
> **Note:** Broadcom switched VMware Workstation Pro to calendar-based version names (such as **`25H2`**, **`26H1`**, and **`26H1u1`**) and made it **100% free** (no license key required). All versions (`17.x` through `26H1u1+`) work identically for this lab:
> 1. Create an account on [https://support.broadcom.com/](https://support.broadcom.com/)
> 2. Log in and select **My Downloads** $\rightarrow$ **Free Software Downloads available HERE** $\rightarrow$ **VMware Workstation Pro**
> 3. Select the latest Windows release (e.g., **`26H1u1`** or **`17.x`**) and accept the terms to download.

#### 2.2 Ubuntu Server ISO
- **Official website:** [https://ubuntu.com/download/alternative-downloads](https://ubuntu.com/download/alternative-downloads)
- **Direct torrent link (Ubuntu 22.04.5 LTS):** [https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso.torrent](https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso.torrent)

---

## 1. Infrastructure Setup

When creating each new VM in VMware Workstation Pro:
- Choose **"Typical"** installation.
- Select **"I will install the operating system later"**.
- On the disk settings page:
  - Select **"Store virtual disk as a single file"** (do NOT split the disk into multiple files).
- During the Ubuntu Server OS installation:
  - In the storage configuration step, **disable LVM (Logical Volume Management)**—uncheck *"Set up this disk as an LVM group"*.
  - Choose **"Use an entire disk"** without LVM. This keeps disk management simple and avoids needing to manually expand logical volumes later.

### 1.1 VM Configuration in VMware Workstation Pro

#### Master Node (`k8s-master`):
- **OS:** Ubuntu Server 22.04.5 LTS
- **CPU:** 2 cores (minimum), 4 cores (recommended)
- **RAM:** 4GB (minimum), 8GB (recommended)
- **Storage:** 50GB (recommended)

#### Worker Node (`k8s-worker`):
- **OS:** Ubuntu Server 22.04.5 LTS
- **CPU:** 2 cores (minimum)
- **RAM:** 2GB (minimum), 4GB (recommended)
- **Storage:** 20GB (minimum)

### 1.2 Network Configuration

For both master and worker nodes in the VMware Workstation VM settings:
1. Set primary network adapter (**Network Adapter 1**) to **NAT** (provides internet access).
2. Add a second network adapter (**Network Adapter 2**) set to **Host-only** (provides a private static network between the VMs and your Windows host).

---

## 2. Basic System Configuration

Run these steps on **both** master and worker nodes.

**First, clone this repository onto each node.** You'll need it for the optional bootstrap script below and later for the labs and break-fix scripts. `git` comes with Ubuntu Server:

```bash
git clone https://github.com/Brazeg/k8s-homelab.git ~/k8s-homelab
```

> **⚡ Want to automate Sections 2 & 3?** After configuring your Netplan IP in Section 2.5, you can run [**`scripts/bootstrap-node.sh`**](../scripts/bootstrap-node.sh) to automatically configure swap, kernel modules, `sysctl`, `/etc/hosts`, `containerd`, `crictl`, and `kubeadm`/`kubelet`/`kubectl`:
> ```bash
> cd ~/k8s-homelab
> # On k8s-master:
> sudo ./scripts/bootstrap-node.sh k8s-master 192.168.56.20
> # On k8s-worker:
> sudo ./scripts/bootstrap-node.sh k8s-worker 192.168.56.21
> ```
> Do Sections 2 and 3 by hand at least once, though. The exam expects you to know what each step does.

### 2.1 Update System

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl openssh-server net-tools nano
```

### 2.2 Disable Swap

Kubernetes (`kubelet`) requires swap memory to be disabled for predictable pod memory management:

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### 2.3 Load Kernel Modules

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

### 2.4 Configure Sysctl

Enable bridged IPv4/IPv6 traffic to pass through `iptables` and enable IPv4 packet forwarding:

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

sudo sysctl --system
```

### 2.5 Configure Network Interfaces on Both Nodes

Get IP address information:

```bash
ip addr show
```

Note the following interfaces:
1. **`lo` (`127.0.0.1`)**: The loopback interface (not used for inter-VM networking).
2. **`ens33` (`192.168.x.x`)**: Your **NAT** interface. You can use this IP address initially for SSH access from your Windows host machine.

**Connect via SSH from Windows** to make copy-pasting commands much easier and enhance the experience:

- **Option A — Windows Terminal / PowerShell (Recommended for a better experience):**
  ```powershell
  ssh username@master-node-ip
  ```
- **Option B — PuTTY:**
  - Enter the IP address of one of the VMs
  - Set the port to `22` (default for SSH)
  - Give the session a name (e.g., `"k8s-master"` or `"k8s-worker"`)
  - Click **"Save"** to save the session and repeat for the other VM

> **Important:** When initializing the Kubernetes cluster on the master node in Step 4, you will use the **Host-only (`ens37`) IP address** (`192.168.56.20`) for the `--apiserver-advertise-address` parameter.

3. **`ens37`**: Your **Host-only** adapter. By default, it starts in a `DOWN` state without an IP address assigned. This interface allows your Kubernetes nodes and Windows host computer to communicate over a dedicated static network (`192.168.56.0/24`).

Bring up the `ens37` interface and assign a temporary IP (optional before Netplan apply):

```bash
sudo ip link set ens37 up
sudo ip addr add 192.168.56.20/24 dev ens37   # Use 192.168.56.21/24 on k8s-worker
```

To make the static IP persistent across reboots, edit the Netplan configuration:

```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Configure `ens33` (DHCP) and `ens37` (Static IP):

```yaml
network:
  ethernets:
    ens33:
      dhcp4: true
    ens37:
      dhcp4: no
      addresses: [192.168.56.20/24]  # Remember to use 192.168.56.21/24 for the worker node
  version: 2
```

Apply the configuration and verify:

```bash
sudo netplan apply
ip addr show
```

Finally, ensure each VM has its own unique hostname (`k8s-master` and `k8s-worker`) and add both Host-Only IPs to `/etc/hosts` on **both** nodes:

```bash
# Run on k8s-master: sudo hostnamectl set-hostname k8s-master
# Run on k8s-worker: sudo hostnamectl set-hostname k8s-worker

cat <<EOF | sudo tee -a /etc/hosts
192.168.56.20 k8s-master
192.168.56.21 k8s-worker
EOF
```

---

## 3. Kubernetes Installation

Perform these steps on **both** master and worker nodes:

### 3.1 Install containerd

Install the container runtime environment (`containerd`) and enable the `systemd` cgroup driver (required by `kubelet`):

```bash
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 3.2 Install Kubernetes Components

Install `kubelet`, `kubeadm`, and `kubectl` and pin (`hold`) their versions to prevent unintended automatic upgrades:

> **Why `v1.29`?** It is end-of-life on purpose. Starting on an old release lets you practice the `v1.29` → `v1.30` → `v1.31` upgrade chain in [Section 8](#8-live-cluster-upgrade-v129--v130-with-running-workloads). Don't run an EOL release for anything real.

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

Because each VM has two network interfaces (`ens33` NAT and `ens37` Host-Only), tell `kubelet` to register the **Host-Only IP** (`192.168.56.20` on master, `192.168.56.21` on worker) as the node's `InternalIP`:

```bash
# On k8s-master (use 192.168.56.21 on k8s-worker):
echo "KUBELET_EXTRA_ARGS=--node-ip=192.168.56.20" | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## 4. Initialize Kubernetes Cluster

Perform these steps on the **master node (`k8s-master`) only**:

### 4.1 Initialize Control Plane

```bash
sudo kubeadm init --pod-network-cidr=172.16.0.0/12 --apiserver-advertise-address=192.168.56.20
```

### 4.2 Set Up kubectl for Non-Root User

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 4.3 Install Calico Network Plugin

Install the Tigera Calico operator:

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml
```

Apply the Calico custom resource configuration matching our `172.16.0.0/12` Pod CIDR:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 172.16.0.0/12
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF
```

---

## 5. Join Worker Node to Cluster

On the **master node**, generate a join command:

```bash
kubeadm token create --print-join-command
```

On the **worker node (`k8s-worker`)**, run the generated command with `sudo -E`:

```bash
sudo -E <join-command>
```

---

## 6. Verify Cluster Setup

On the **master node**, verify both nodes reach the `Ready` state:

```bash
kubectl get nodes -o wide
```

> **💡 Pro Tip for CKA Practice:** Once both nodes show `Ready` and all pods in `kubectl get pods -A` are `Running`, **take a VMware Snapshot** of both `k8s-master` and `k8s-worker` (e.g., named `"Clean-Cluster-State"`). This allows you to practice destructive CKA tasks (like `etcd` restore, cluster version upgrades, or breaking node components) and roll back to a clean cluster in 10 seconds!

> **Core setup done.** Sections 7 and 8 are optional extras. If you'd rather run `kubectl` from Windows PowerShell than over SSH, do [Section 10](#10-accessing-kubernetes-cluster-from-windows-host-machine) now. Otherwise jump to [Section 11: Next Steps](#11-next-steps).

---

## 7. Install Monitoring Stack (Prometheus and Grafana)

> **Optional.** Monitoring isn't on the CKA. This section gives you Grafana dashboards to watch, a realistic workload for the live upgrade in Section 8, and practice with Helm (which *is* on the CKA, see [Lab 1.4](../01-cluster-architecture/README.md#lab-14-kustomize--helm-basics)).

Perform these steps on the **master node**:

### 7.1 Install Helm

```bash
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install -y helm
```

### 7.2 Install Prometheus and Grafana

```bash
# Create dedicated namespace for monitoring
kubectl create namespace monitoring

# Add Prometheus Helm repository
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install Prometheus and Grafana stack in monitoring namespace
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword="prom-operator"
```

### 7.3 Access Grafana

To access Grafana securely using port-forwarding with SSH tunneling:

1. On your **Windows host machine** (not inside the VM), open a new terminal and run:
   ```powershell
   ssh -L 3000:localhost:3000 username@192.168.56.20
   ```
2. Once connected, run the `port-forward` command in the SSH session:
   ```bash
   kubectl port-forward deployment/monitoring-grafana 3000 --namespace=monitoring
   ```

Access Grafana at `http://localhost:3000` in your browser.

**Default credentials:**
- **Username:** `admin`
- **Password:** `prom-operator`

### 7.4 OPTIONAL: Access Grafana and Prometheus Using NodePort

*As an alternative to SSH tunneling, you can expose Grafana and Prometheus via the Kubernetes `NodePort` service type. **Note:** This exposes the ports on your node IPs and is less secure in non-isolated networks without additional security measures.*

Save the following manifest as `monitoring-nodeports.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prometheus-nodeport
  namespace: monitoring
  labels:
    app: prometheus
spec:
  type: NodePort
  ports:
    - port: 9090
      targetPort: 9090
      nodePort: 30909  # Port range: 30000-32767
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: prometheus
    prometheus: monitoring-kube-prometheus-prometheus
---
apiVersion: v1
kind: Service
metadata:
  name: grafana-nodeport
  namespace: monitoring
  labels:
    app: grafana
spec:
  type: NodePort
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30300  # Port range: 30000-32767
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: grafana
```

Apply the manifest with `kubectl`:

```bash
kubectl apply -f monitoring-nodeports.yaml
```

*(To remove the NodePort services later, run: `kubectl delete -f monitoring-nodeports.yaml`)*

From your Windows host browser, access:
- **Prometheus:** `http://192.168.56.20:30909`
- **Grafana:** `http://192.168.56.20:30300`

---

## 8. Live Cluster Upgrade (`v1.29` → `v1.30`) With Running Workloads

In both real-world production and the **CKA exam**, you never upgrade an empty cluster—you upgrade a cluster while **live applications, `PodDisruptionBudgets`, and monitoring stacks** are actively serving traffic.

> **Optional, advanced: do this after [Lab 1.2](../01-cluster-architecture/README.md#lab-12-upgrading-a-kubeadm-cluster-v129--v130).** Lab 1.2 teaches the basic upgrade steps. This section repeats them on a cluster serving live traffic. Either one moves your cluster from `v1.29` to `v1.30`, so **revert to your `Clean-Cluster-State` snapshot afterwards** to keep a `v1.29` cluster for practicing again.
>
> **⚠️ Take a Snapshot First:** Before starting this stage, take a VMware snapshot of both `k8s-master` and `k8s-worker` so you can practice live upgrades repeatedly.

### 8.1 Deploy a Live Application with `PodDisruptionBudget` & Uptime Monitor

In addition to the Prometheus & Grafana stack already running in the `monitoring` namespace, deploy a live 2-replica web service (`live-storefront`) protected by a `PodDisruptionBudget` (`minAvailable: 1`) and exposed on `NodePort: 30080`:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: live-prod
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: live-storefront
  namespace: live-prod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: live-storefront
  template:
    metadata:
      labels:
        app: live-storefront
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 2
          periodSeconds: 3
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: storefront-pdb
  namespace: live-prod
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: live-storefront
---
apiVersion: v1
kind: Service
metadata:
  name: storefront-svc
  namespace: live-prod
spec:
  type: NodePort
  selector:
    app: live-storefront
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
EOF
```

Verify the pods are running and open a **second PowerShell terminal on your Windows host** to continuously monitor live HTTP responses every second during the upgrade:

```powershell
# Run in a separate Windows PowerShell window to watch live uptime during the upgrade:
while ($true) {
  try {
    $r = Invoke-WebRequest -Uri "http://192.168.56.20:30080" -UseBasicParsing -TimeoutSec 2
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - LIVE APP UP (HTTP $($r.StatusCode))" -ForegroundColor Green
  } catch {
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - DOWNTIME DETECTED!" -ForegroundColor Red
  }
  Start-Sleep -Seconds 1
}
```

### 8.2 The 2-Node Live Upgrade Trap (Control-Plane Taint & PDBs)

Look at where your pods are running right now:

```bash
kubectl get pods -n live-prod -o wide
kubectl get pods -n monitoring -o wide
```

Everything is scheduled on **`k8s-worker`** because `k8s-master` has the default taint `node-role.kubernetes.io/control-plane:NoSchedule`.

**What happens if you try to `kubectl drain k8s-worker` without preparing `k8s-master`?**
1. Kubernetes evicts 1 replica of `live-storefront`, which becomes `Pending` because `k8s-master` rejects it due to the `control-plane:NoSchedule` taint.
2. When `kubectl drain` tries to evict the 2nd replica, the `PodDisruptionBudget` (`minAvailable: 1`) **blocks the drain** with:
   `error when evicting pods/"live-storefront-...": Cannot evict pod as it would violate the pod's disruption budget.`
3. Even without a PDB, draining your only worker node while `k8s-master` is tainted would cause **100% application downtime**!

### 8.3 Upgrade the Control Plane Node (`k8s-master`)

Perform these steps on **`k8s-master`**. Because application pods are currently on `k8s-worker`, upgrading the control plane will not interrupt traffic:

1. **Switch the Kubernetes APT repository from `v1.29` to `v1.30`:**
   ```bash
   curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
   sudo apt update
   ```

2. **Find the latest `1.30.x` patch version and upgrade `kubeadm`:**
   ```bash
   sudo apt-cache madison kubeadm
   # Replace 1.30.5-1.1 below if a newer 1.30.x patch is listed
   sudo apt-mark unhold kubeadm
   sudo apt install -y kubeadm=1.30.5-1.1
   sudo apt-mark hold kubeadm
   ```

3. **Verify the upgrade plan and upgrade the control plane components:**
   ```bash
   sudo kubeadm version
   sudo kubeadm upgrade plan
   sudo kubeadm upgrade apply v1.30.5 -y
   ```

4. **Drain `k8s-master`, upgrade `kubelet` & `kubectl`, and uncordon:**
   ```bash
   kubectl drain k8s-master --ignore-daemonsets

   sudo apt-mark unhold kubelet kubectl
   sudo apt install -y kubelet=1.30.5-1.1 kubectl=1.30.5-1.1
   sudo apt-mark hold kubelet kubectl

   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   kubectl uncordon k8s-master
   ```

Check your Windows PowerShell uptime monitor—`live-storefront` (`http://192.168.56.20:30080`) continued serving `HTTP 200` even while `kube-apiserver` restarted!

### 8.4 Drain Live Workloads & Upgrade the Worker Node (`k8s-worker`)

Now we need to upgrade `k8s-worker` without dropping traffic or deadlocking on `storefront-pdb`:

1. **On `k8s-master`, temporarily remove the `control-plane:NoSchedule` taint so `k8s-master` can host workloads while `k8s-worker` is upgraded:**
   ```bash
   kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule-
   ```

2. **Drain `k8s-worker` and watch the `PodDisruptionBudget` gracefully migrate pods to `k8s-master` one by one:**
   ```bash
   kubectl drain k8s-worker --ignore-daemonsets --delete-emptydir-data
   kubectl get pods -n live-prod -o wide
   ```
   *(Notice how `storefront-pdb` ensures the first evicted pod becomes `Running` & `Ready` on `k8s-master` before allowing the second pod on `k8s-worker` to terminate—zero failed requests in your PowerShell monitor!)*

3. **SSH into `k8s-worker` (`ssh username@192.168.56.21`) and upgrade `kubeadm`, `kubelet`, and `kubectl`:**
   ```bash
   curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
   echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
   sudo apt update

   sudo apt-mark unhold kubeadm
   sudo apt install -y kubeadm=1.30.5-1.1
   sudo apt-mark hold kubeadm

   # Upgrade worker node configuration
   sudo kubeadm upgrade node

   sudo apt-mark unhold kubelet kubectl
   sudo apt install -y kubelet=1.30.5-1.1 kubectl=1.30.5-1.1
   sudo apt-mark hold kubelet kubectl

   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   ```

### 8.5 Rebalance Workloads & Chaining Further Upgrades (`v1.30` → `v1.31`)

1. **Back on `k8s-master`, uncordon `k8s-worker` and verify both nodes are on `v1.30.5`:**
   ```bash
   kubectl uncordon k8s-worker
   kubectl get nodes -o wide
   ```

2. **Restore the `control-plane:NoSchedule` taint on `k8s-master` and rolling-restart deployments so workloads move back to `k8s-worker` with zero downtime:**
   ```bash
   kubectl taint nodes k8s-master node-role.kubernetes.io/control-plane:NoSchedule
   kubectl rollout restart deployment/live-storefront -n live-prod
   kubectl rollout status deployment/live-storefront -n live-prod
   kubectl get pods -n live-prod -o wide
   ```

> **📚 Official Kubernetes Version Skew Policy (Jumping Multiple Minor Versions):**
> Kubernetes does **not** support skipping minor versions during an upgrade (for example, jumping directly from `v1.29` to `v1.31`). To upgrade across multiple minor releases (`v1.29` → `v1.31`), complete the `v1.29` → `v1.30` upgrade above, verify all nodes and pods are healthy, and then repeat Steps 8.3–8.5 using the `v1.31` repository (`https://pkgs.k8s.io/core:/stable:/v1.31/deb/`).

---

## 9. Troubleshooting and Verification

> **🔧 Encountering errors during setup or after a reboot?** Check out the dedicated [**Common Problems & Solutions Guide**](../Common%20problems/Readme.md) for step-by-step fixes for Swap issues, `containerd` / `crictl` runtime errors, and API server connection failures.

### 9.1 Check Node Status

```bash
kubectl get nodes
kubectl describe nodes
```

### 9.2 Check Pod Status

```bash
kubectl get pods --all-namespaces
```

### 9.3 Check Logs

```bash
kubectl logs <pod-name> -n <namespace>
```

### 9.4 Check Services

```bash
kubectl get services --all-namespaces
```

---

## 10. Accessing Kubernetes Cluster from Windows Host Machine

Since you're using Windows and already have SSH access to your VMs, you can run `kubectl` directly from PowerShell on your host machine:

1. **Install `kubectl` on Windows** (using Winget or from [kubernetes.io](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/)):
   ```powershell
   winget install Kubernetes.kubectl
   ```

2. **Create the `.kube` directory and config file in PowerShell:**
   ```powershell
   mkdir "$env:USERPROFILE\.kube" -Force
   New-Item -Path "$env:USERPROFILE\.kube\config" -Type File -Force
   ```

3. **Copy the `kubeconfig` from your master node:**
   Copy `/etc/kubernetes/admin.conf` (or `~/.kube/config`) directly via `scp` from PowerShell:
   ```powershell
   scp username@192.168.56.20:~/.kube/config "$env:USERPROFILE\.kube\config"
   ```
   *(Alternatively, copy the contents of `~/.kube/config` from your SSH session and paste them into `%USERPROFILE%\.kube\config` using Notepad).*

4. **Set the `KUBECONFIG` environment variable in PowerShell (optional if using the default `~/.kube/config` path):**
   ```powershell
   $env:KUBECONFIG = "$env:USERPROFILE\.kube\config"
   ```

5. **Verify connectivity to the Master Node API Server (`192.168.56.20:6443`):**
   ```powershell
   ping 192.168.56.20
   Test-NetConnection 192.168.56.20 -Port 6443
   ```
   If the connection is not successful, verify that the VMware Host-Only adapter on your Windows machine is on the `192.168.56.0/24` subnet:
   - Press `Win + R`, type `ncpa.cpl`, and press Enter.
   - Right-click **"VMware Network Adapter VMnet1"** and choose **Properties**.
   - Select **"Internet Protocol Version 4 (TCP/IPv4)"** and click **Properties**.
   - Ensure **"Use the following IP address"** is set to an IP in the same subnet (e.g., `192.168.56.1` with subnet mask `255.255.255.0`), then apply the changes.

Now you can run `kubectl get nodes` directly from your Windows host terminal!

---

## 11. Next Steps

Your 2-node cluster is ready, and the repo is already cloned at `~/k8s-homelab` on both nodes (Section 2). Before you start:

1. **Take the `Clean-Cluster-State` snapshot** from [Section 6](#6-verify-cluster-setup) if you haven't yet. Several labs are destructive.
2. **Head to the [CKA Study Hub](../Readme.md#cka-study-hub--hands-on-lab-modules)** and begin with the ⚡ [cheatsheet](../cheatsheets/cka-exam-day-survival-guide.md).
