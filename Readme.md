
Complete guide to setting up a Kubernetes lab environment on a virtual Ubuntu machine virtualized with VMware Workstation Pro on Windows 11

<img src="Space Captain.png" alt="Lab Setup" title="Kubernetes Space Captain" width="800"/>

- [Overview](#overview)
- [Prerequisites for Kubernetes Lab Environment](#prerequisites-for-kubernetes-lab-environment)
- [1. Infrastructure Setup](#1-infrastructure-setup)
  - [1.1 VM Configuration in VMware Workstation Pro](#11-vm-configuration-in-vmware-workstation-pro)
    - [Master Node (k8s-master):](#master-node-k8s-master)
    - [Worker Node (k8s-worker):](#worker-node-k8s-worker)
  - [1.2 Network Configuration](#12-network-configuration)
- [2. Basic System Configuration](#2-basic-system-configuration)
  - [2.1 Update System](#21-update-system)
  - [2.2 Disable Swap](#22-disable-swap)
  - [2.3 Load Kernel Modules](#23-load-kernel-modules)
  - [2.4 Configure Sysctl](#24-configure-sysctl)
  - [2.5 Configure Network Interfaces on both nodes](#25-configure-network-interfaces-on-both-nodes)
- [3. Kubernetes Installation](#3-kubernetes-installation)
  - [3.1 Install containerd](#31-install-containerd)
  - [3.2 Install Kubernetes Components](#32-install-kubernetes-components)
- [4. Initialize Kubernetes Cluster](#4-initialize-kubernetes-cluster)
  - [4.1 Initialize Control Plane](#41-initialize-control-plane)
  - [4.2 Set Up kubectl for Non-Root User](#42-set-up-kubectl-for-non-root-user)
  - [4.3 Install Calico Network Plugin](#43-install-calico-network-plugin)
- [5. Join Worker Node to Cluster](#5-join-worker-node-to-cluster)
- [6. Verify Cluster Setup](#6-verify-cluster-setup)
- [7. Install Monitoring Stack (Prometheus and Grafana)](#7-install-monitoring-stack-prometheus-and-grafana)
  - [7.1 Install Helm](#71-install-helm)
  - [7.2 Install Prometheus and Grafana](#72-install-prometheus-and-grafana)
  - [7.3 Access Grafana](#73-access-grafana)
  - [7.4 OPTIONAL Access Grafana and Promotheus using NodePort](#74-optional-access-grafana-and-promotheus-using-nodeport)
  - [8.1 Check Node Status](#81-check-node-status)
  - [8.2 Check Pod Status](#82-check-pod-status)
  - [8.3 Check Logs](#83-check-logs)
  - [8.4 Check Services](#84-check-services)
- [9. Accessing Kubernetes Cluster from Windows Host Machine](#9-accessing-kubernetes-cluster-from-windows-host-machine)


======================================
## Overview

This guide will help you create a production-like Kubernetes cluster with 2 nodes (1 master, 1 worker) running on Ubuntu VMs. Instead of clicking through VM windows, you'll learn to manage everything like a pro:

- Control your VMs through SSH directly from your Windows terminal 🚀
- Execute commands remotely without accessing the VM console 💻
- Run kubectl commands from your Windows machine 🎮
- Set up everything from scratch for deep understanding 🔧

Unlike simpler alternatives like Minikube or Kind, this setup mirrors a real production environment with multiple nodes, true networking, and SSH-based management. You'll gain hands-on experience with the complete installation process, network configuration, and infrastructure management.

Think of it as your personal production environment - all the real-world practices, none of the complexity of cloud costs! Perfect for learning, testing, and experimenting with Kubernetes.


## Prerequisites for Kubernetes Lab Environment
1. Hardware Requirements

Host Computer Specifications:

CPU: Intel/AMD processor with virtualization support (VT-x/AMD-V)
RAM: Minimum 8GB (16GB recommended)
Storage: At least 40GB free space
Operating System: Windows 11


2. Software Requierments

2.1 VMware Workstation Pro 17 (Free for personal useage)
Note: The VMware Workstation 17 installation process might be more complicated currently due to the recent Broadcom acquisition of VMware.
 * Create an account on https://broadcom.com
 * go to https://support.broadcom.com/
 * Choose Cloud Foundation from the upper right menu
 * Now the installation file of VMware Workstation can be found in the My Downlaod section


2.2 Ubuntu Server ISO

Downloadable from the offical website: https://ubuntu.com/download/alternative-downloads

Direct link: webtorrent: https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso.torrent


1\. Infrastructure Setup
------------------------
* Choose "Typical" installation when creating new VM
* Select "I will install the operating system later" option
* On the disk settings page:
    * Select "Store virtual disk as a single file"
    * Do NOT split disk into multiple files


* During Ubuntu Server installation:
    * In the storage configuration step, disable LVM (Logical Volume Management)
    * Choose "Use entire disk" without LVM
    * This makes the disk configuration simpler and more straightforward for a lab environment

### 1.1 VM Configuration in VMware Workstation Pro

use typical installation
disable lg groups
use one file for storage

#### Master Node (k8s-master):

*   OS: Ubuntu Server 22.04.5 LTS
*   CPU: 2 cores (minimum), 4 cores (recommended)
*   RAM: 4GB (minimum), 8GB (recommended)
*   Storage: 50GB (recommended)

#### Worker Node (k8s-worker):

*   OS: Ubuntu Server 22.04.5 LTS
*   CPU: 2 cores (minimum)
*   RAM: 2GB (minimum)
*   Storage: 20GB (minimum)

### 1.2 Network Configuration

For both master and worker nodes in the the VMware Workstation VM settings:

1.  Set primary network adapter (Network Adapter 1) to NAT
2.  Add a second network adapter (Network Adapter 2) set to Host-only

2\. Basic System Configuration
------------------------------

Run these steps on both master and worker nodes:

### 2.1 Update System

    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl openssh-server net-tools nano

### 2.2 Disable Swap

    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

### 2.3 Load Kernel Modules

    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
    overlay
    br_netfilter
    EOF
    sudo modprobe overlay
    sudo modprobe br_netfilter

### 2.4 Configure Sysctl

    cat << EOF | sudo tee /etc/sysctl.d/k8s.conf
    net.bridge.bridge-nf-call-iptables = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    net.ipv4.ip_forward = 1
    EOF
    sudo sysctl --system

### 2.5 Configure Network Interfaces on both nodes
Get IP address information:

    ip addr show

Note the following:
1. The lo interface (127.0.0.1) is the loopback interface, which we don't use for networking between VMs.
2. The ens33 interface (192.x.x.x) is likely your NAT interface. This is the IP address you can use for SSH access from your host machine.

Use one of these options to ease the copy pasting process and enhance the experince:

Either open 2 sessions with the software Putty, as follows:
* Enter the IP address of one of the VMs
* Set the port to 22 (default for SSH)
* Give the session a name (e.g., *"k8s-master" or "k8s-worker")
* Click "Save" to save this session
* Repeat for the other VM

OR

use ssh directly from powershell or windows terminal (better experince):

    ssh username@master-node-ip

*Remember, when you're initializing the Kubernetes cluster on the master node, you'll use the Host-only IP address of the master node for the --apiserver-advertise-address parameter.*


3. The ens37 interface is your Host-only adapter, but it's currently in a DOWN state and doesn't have an IP address assigned.
The ens37 host-only interface is needed to allow your VMs (k8s nodes) to communicate with each other and with your host computer in an isolated network, without needing access to the external internet


Bring up the ens37 interface:
    
    sudo ip link set ens37 up

Assign an IP address to this interface:

    sudo ip addr add 192.168.56.20/24 dev ens37



Edit the Netplan configuration:

    sudo nano /etc/netplan/00-installer-config.yaml

Add configuration for `ens37`:

    network:
      ethernets:
        ens33:
          dhcp4: true
        ens37:
          dhcp4: no
          addresses: [192.168.56.20/24]  # Remember to use 192.168.56.21/24 for worker node
      version: 2

Apply the configuration:

    sudo netplan apply

Verify with:

    ip addr show

3\. Kubernetes Installation
--------------------------

Perform these steps on both master and worker nodes:

### 3.1 Install containerd

Installling the container runtime enviroment 

    sudo apt install -y containerd
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd

### 3.2 Install Kubernetes Components

installing kubernetes components and holding them from automatic updates

    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl

4\. Initialize Kubernetes Cluster
--------------------------------

Perform these steps on the master node:

### 4.1 Initialize Control Plane

    sudo kubeadm init --pod-network-cidr=172.16.0.0/12 --apiserver-advertise-address=192.168.56.20

### 4.2 Set Up kubectl for Non-Root User

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

### 4.3 Install Calico Network Plugin

    kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.3/manifests/tigera-operator.yaml

Apply Calico configuration:

    cat << EOF | kubectl apply -f -
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

5\. Join Worker Node to Cluster
------------------------------

On the master node, generate a join command:

    kubeadm token create --print-join-command

On the worker node, run the generated command with sudo -E:

    sudo -E <join-command>

6\. Verify Cluster Setup
-----------------------

On the master node:

    kubectl get nodes

7\. Install Monitoring Stack (Prometheus and Grafana)
----------------------------------------------------

On the master node:

### 7.1 Install Helm

    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install helm

### 7.2 Install Prometheus and Grafana

    # Create dedicated namespace for monitoring
    kubectl create namespace monitoring
    
    # Add Prometheus helm repository
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    
    # Install Prometheus and Grafana stack in monitoring namespace
    helm install monitoring prometheus-community/kube-prometheus-stack \
      --namespace monitoring \
      --create-namespace \
      --set grafana.adminPassword="prom-operator"

### 7.3 Access Grafana

To access Grafana, use port-forwarding with SSH Tunneling:

1. On your host machine (not the VM), open a new terminal and run:

        ssh -L 3000:localhost:3000 username@master-node-ip

2. Once connected, run the port-forward command in the SSH session:

        kubectl port-forward deployment/monitoring-grafana 3000


Access Grafana at `http://localhost:3000` in your browser.

Default credentials:

*   Username: admin
*   Password: prom-operator

###  7.4 OPTIONAL Access Grafana and Promotheus using NodePort
*Alternativ to SSH Tunneling you can use the kubernetes service type NodePort, BUT KEEP IN MIND this is less secure without additional measuerments*

Write the following content into a monitoring-nodeports.yaml file then apply it with kubectl:

    kubectl apply -f monitoring-nodeports.yaml

*reverse with*:  kubectl delete -f monitoring-nodeports.yaml

monitoring-nodeports.yaml content: 

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
        nodePort: 30909  # You can choose a port between 30000-32767
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
        nodePort: 30300  # You can choose a port between 30000-32767
        protocol: TCP
        name: http
    selector:
        app.kubernetes.io/name: grafana


From your Windows machine, try accessing in the browser:

* http://192.168.56.20:30909 for Prometheus
* http://192.168.56.20:30300 for Grafana



8. Troubleshooting and Verification
-----------------------------------

### 8.1 Check Node Status

    kubectl get nodes
    kubectl describe nodes

### 8.2 Check Pod Status

    kubectl get pods --all-namespaces

### 8.3 Check Logs

    kubectl logs <pod-name> -n <namespace>

### 8.4 Check Services

    kubectl get services --all-namespaces

9\. Accessing Kubernetes Cluster from Windows Host Machine
---------------------------------------------------------

Since you're using Windows and already have SSH access to your VMs, here's how to set up kubectl access from your Windows machine: First, ensure kubectl is installed on your Windows machine: You can install it using winget: winget install Kubernetes.kubectl Or download it directly from kubernetes.io

1.  Create the kubectl config directory (if it doesn't exist) and the config file using powershell:
    
        mkdir "$env:USERPROFILE\.kube"
        New-Item -Path "$env:USERPROFILE\.kube\config" -Type File -Force

2.  Copy the content of kubeconfig from the master node using your existing SSH connection

3.  Paste this data into the %USERPROFILE%\\.kube\config file on your windows machine using Notepad or your preferred text editor then run this in powershell to set the enviroment variable:

        $env:KUBECONFIG = "C:\Users\yourUserName\.kube\config" 
    
4.    Edit the config file using Notepad or your preferred text editor: Open %USERPROFILE%\.kube\config
    
5.  try pinging the `master node's IP: https://192.168.56.20:6443`, if not successfull you have to make sure the Network adapter is set correctly by VMware on your windows machine, for that do the following:

    * type ncpa.cpl in the Run dialog or search bar

    * Right-click on "VMware Network Adapter VMnet1" and choose Properties

    * Select "Internet Protocol Version 4 (TCP/IPv4)" and click Properties

    * Make sure that the IP address in the section "Use the following IP address" is the right one, then apply the changes.


Now you can use kubectl commands from your host machine to interact with your Kubernetes cluster. 

``
