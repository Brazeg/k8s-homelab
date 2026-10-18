#!/usr/bin/env bash
# Automated Node Bootstrap Script (Covers Sections 2 & 3 of vm/README.md)
# Usage:
#   On Master Node: sudo ./scripts/bootstrap-node.sh k8s-master 192.168.56.20
#   On Worker Node: sudo ./scripts/bootstrap-node.sh k8s-worker 192.168.56.21

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a  # no interactive apt/needrestart prompts

NODE_HOSTNAME="${1:-}"
NODE_IP="${2:-}"
K8S_VERSION="v1.29"

if [[ $EUID -ne 0 ]]; then
   echo "❌ Please run this script with sudo: sudo $0 <hostname> <host-only-ip>"
   exit 1
fi

if [[ -z "$NODE_HOSTNAME" || -z "$NODE_IP" ]]; then
   echo "Usage: sudo $0 <hostname> <host-only-ip>"
   echo "Example (Master): sudo $0 k8s-master 192.168.56.20"
   echo "Example (Worker): sudo $0 k8s-worker 192.168.56.21"
   exit 1
fi

echo "🚀 [1/7] Setting hostname to '$NODE_HOSTNAME' and updating /etc/hosts..."
hostnamectl set-hostname "$NODE_HOSTNAME"
grep -q "192.168.56.20 k8s-master" /etc/hosts || echo "192.168.56.20 k8s-master" >> /etc/hosts
grep -q "192.168.56.21 k8s-worker" /etc/hosts || echo "192.168.56.21 k8s-worker" >> /etc/hosts

echo "🚀 [2/7] Updating packages and installing prerequisites..."
apt-get update && apt-get upgrade -y
apt-get install -y curl gpg apt-transport-https ca-certificates openssh-server net-tools nano

echo "🚀 [3/7] Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "🚀 [4/7] Loading kernel modules (overlay, br_netfilter) and sysctl settings..."
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

echo "🚀 [5/7] Installing and configuring containerd (SystemdCgroup = true)..."
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

cat <<EOF > /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "🚀 [6/7] Installing kubeadm, kubelet, and kubectl ($K8S_VERSION)..."
mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key" | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "🚀 [7/7] Configuring kubelet --node-ip=$NODE_IP..."
echo "KUBELET_EXTRA_ARGS=--node-ip=${NODE_IP}" > /etc/default/kubelet
systemctl daemon-reload
systemctl restart kubelet

echo "✅ Node '$NODE_HOSTNAME' ($NODE_IP) is ready for Kubernetes!"
