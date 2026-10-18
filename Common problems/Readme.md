# Kubernetes Cluster Setup: Common Issues and Solutions

[⬅ Back to VM Lab Setup](../vm/README.md) · [Main CKA Hub](../Readme.md)

When setting up a Kubernetes cluster, particularly in this virtualized environment, there are two critical issues that commonly occur and can prevent your cluster from functioning properly:

1. **Swap Memory Active**: Kubernetes requires swap to be disabled for consistent performance and resource management. This is a prerequisite that often gets overlooked.
2. **Container Runtime Misconfiguration**: Issues with `containerd` configuration and its interaction with Kubernetes, especially after fresh installations or updates.

These issues frequently appear after:
- Fresh installations
- System updates
- Moving VMs to different locations
- Changing system configurations

This guide provides a clear breakdown of how to identify and fix these issues, along with a comprehensive checklist for a successful Kubernetes cluster setup.

---

## 1. Pre-Installation Checklist

Before starting installation, verify:

- [ ] CPU virtualization enabled in BIOS (VT-x / AMD-V)
- [ ] Minimum 2 CPU cores allocated
- [ ] Minimum 4GB–8GB RAM allocated
- [ ] Minimum 20GB disk space (50GB recommended for master node)
- [ ] Ubuntu Server 22.04.5 LTS installed

---

## 2. Common Issues and Solutions

### 2.1 Swap Memory Issues

**Symptoms:**
- Error in `kubelet` logs: `"failed to run Kubelet: running with swap on is not supported"`
- Kubernetes components fail to start
- `kubeadm init` fails with swap-related preflight errors

**Solution:**
```bash
# Disable swap immediately
sudo swapoff -a

# Permanently disable swap in /etc/fstab
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Verify swap is disabled (should show 0B for Swap)
free -h
```

### 2.2 Container Runtime Issues

**Symptoms:**
- Errors with `crictl` commands about `"dockershim.sock"`
- Multiple runtime endpoints errors
- API server connection refused
- Pods stuck in `ContainerCreating` state

> **⚠️ Destructive.** This deletes every container image and container on the node. Try the targeted checks first (`systemctl status containerd`, `journalctl -u containerd`, and `SystemdCgroup = true` in `/etc/containerd/config.toml`). Use this only on a fresh node that won't recover any other way.

**Complete Solution:**
```bash
# 1. Clean existing containerd configuration
sudo systemctl stop containerd
sudo rm -rf /etc/containerd/*
sudo rm -rf /var/lib/containerd/*

# 2. Create proper containerd configuration with SystemdCgroup = true
cat <<EOF | sudo tee /etc/containerd/config.toml
version = 2
[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"
    [plugins."io.containerd.grpc.v1.cri".containerd]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
          runtime_type = "io.containerd.runc.v2"
          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
            SystemdCgroup = true
EOF

# 3. Configure crictl to use containerd socket
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

# 4. Restart services
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl restart kubelet
```

### 2.3 API Server Connection Issues

**Symptoms:**
- `kubectl get nodes` returns `"The connection to the server ...:6443 was refused"`
- Unable to join worker nodes
- Dashboard or other services can't connect to the API server

> **⚠️ Last resort: this rebuilds the whole cluster.** A refused connection usually means the `kube-apiserver` static pod is down, and that is diagnosable. Work through the [troubleshooting flowchart](../05-troubleshooting-break-fix/README.md#1-systematic-cka-troubleshooting-flowchart) and [Scenario 02](../05-troubleshooting-break-fix/scenario-02-apiserver-down/SOLUTION.md) first (`crictl ps -a`, `crictl logs`, `/etc/kubernetes/manifests/`). In the exam, a reset is never the answer. Use this only if `kubeadm init` itself went wrong during setup.

**Solution:**
```bash
# 1. Complete reset of Kubernetes
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d/*
sudo rm -rf $HOME/.kube/config
sudo rm -rf /var/lib/etcd/*

# 2. Reinitialize with the explicit Host-Only (ens37) IP address (192.168.56.20)
sudo kubeadm init --pod-network-cidr=172.16.0.0/12 --apiserver-advertise-address=192.168.56.20

# 3. Set up kubectl configuration
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
*(Remember to re-apply the Calico network plugin after resetting the cluster!)*

---

## 3. Verification Steps

After fixing issues, verify:

```bash
# Check node status
kubectl get nodes

# Check all system pods
kubectl get pods -n kube-system

# Verify container runtime pods
sudo crictl ps

# Check service status
sudo systemctl status containerd
sudo systemctl status kubelet
```

---

## 4. When to Use These Solutions

Apply these fixes when:
- Setting up a new cluster
- After system updates
- After VM migration or cloning
- After network configuration changes
- When pods fail to start
- When worker nodes can't join

**Order of Operations:**
1. **Always fix swap issues first:** It is a strict prerequisite for `kubelet` to run.
2. **Then address container runtime (`containerd`) issues:** It directly controls how control-plane static pods and workloads are started.
3. **Finally, handle Kubernetes (`kubeadm`) configuration.**

**Additional Tips (Especially for CKA Prep):**
- Backup and document any custom configurations and modifications.
- Use `kubectl describe` and `kubectl get events --sort-by='.lastTimestamp'` for detailed investigation.
- Check node-level logs with `sudo journalctl -xeu kubelet` for detailed `kubelet` errors.
- Remember to apply the network plugin (Calico) after cluster initialization so CoreDNS and nodes become `Ready`.
- Document IP addresses and ports used across nodes.

---

## 5. Monitoring the Fix

After applying fixes, monitor:
- **Node status:** `kubectl get nodes -o wide`
- **Pod status:** `kubectl get pods -A`
- **System logs:** `sudo journalctl -xeu kubelet`
- **Container runtime status:** `sudo crictl ps`
