# CKA Exam Day Survival Guide & Speed Cheatsheet

[⬅ Back to Main CKA Hub](../Readme.md)

The CKA exam gives you **2 hours** to solve **15–20 performance-based tasks** across multiple clusters. Speed and accuracy are everything. Use this cheatsheet during your homelab practice so these commands become automatic muscle memory.

---

## 1. First 60 Seconds Exam Setup (`.bashrc` & `.vimrc`)

Run this immediately when your exam terminal opens:

```bash
# 1. Shell aliases & environment variables for rapid YAML generation
cat <<'EOF' >> ~/.bashrc
source <(kubectl completion bash)   # already loaded in the exam; needed in your homelab
alias k=kubectl
complete -o default -F __start_kubectl k
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
EOF
source ~/.bashrc

# 2. Configure Vim for clean 2-space YAML indentation
cat <<'EOF' > ~/.vimrc
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set number
EOF
```

Now you can type:
- `k get po -A` instead of `kubectl get pods --all-namespaces`
- `k run mypod --image=nginx $do > pod.yaml`
- `k delete po mypod $now` (deletes a pod immediately without waiting 30 seconds!)

---

## 2. Imperative Commands (Never Write YAML From Scratch!)

```bash
# Pods
k run web --image=nginx:alpine --port=80 --labels="env=prod,tier=frontend"
k run test --image=busybox:1.36 --rm -it --restart=Never -- sh

# Deployments & Scaling
k create deploy app --image=nginx:1.25 --replicas=3
k scale deploy app --replicas=5
k set image deploy/app nginx=nginx:1.26

# Services
k expose pod web --name=web-svc --port=80 --target-port=80 --type=NodePort
k expose deploy app --name=app-svc --port=8080 --target-port=80

# ConfigMaps & Secrets
k create cm app-config --from-literal=APP_ENV=prod --from-file=config.properties
k create secret generic app-secret --from-literal=API_KEY=12345

# Jobs & CronJobs
k create job backup --image=busybox -- echo "Backup complete"
k create cronjob nightly --image=busybox --schedule="0 2 * * *" -- echo "Nightly run"

# RBAC & ServiceAccounts
k create sa build-bot
k create role pod-reader --verb=get,list,watch --resource=pods
k create clusterrole node-reader --verb=get,list --resource=nodes
k create rolebinding bot-pod-reader --role=pod-reader --serviceaccount=default:build-bot
k create clusterrolebinding bot-node-reader --clusterrole=node-reader --serviceaccount=default:build-bot
```

---

## 3. Finding YAML Fields Without Memorizing (`kubectl explain`)

Forgot the exact indentation for `livenessProbe`, `tolerations`, or `HTTPRoute`? Use `kubectl explain`:

```bash
k explain pod.spec.containers.livenessProbe
k explain pod.spec.tolerations
k explain pod.spec.affinity.nodeAffinity --recursive
k explain networkpolicy.spec.ingress
k explain httproute.spec.rules
```

---

## 4. `jsonpath`, Sorting & Filtering One-Liners

```bash
# Sort Pods by restart count or creation timestamp
k get pods -A --sort-by='.status.containerStatuses[0].restartCount'
k get events -A --sort-by='.lastTimestamp'

# Sort PersistentVolumes by capacity
k get pv --sort-by='.spec.capacity.storage'

# Get all Node Internal IPs using jsonpath
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}{"\n"}'

# Decode a Secret value quickly
k get secret my-secret -o jsonpath='{.data.password}' | base64 -d && echo
```

---

## 5. Node, Control Plane & Runtime Debugging Commands

When `kubectl` isn't working or a node is `NotReady`, SSH into the node and run:

```bash
# 1. Check kubelet and containerd systemd services
sudo systemctl status kubelet
sudo systemctl status containerd
sudo journalctl -xeu kubelet --no-pager | tail -n 40

# 2. Inspect running/exited containers directly via CRI (bypasses API server!)
sudo crictl ps -a
sudo crictl logs <container-id>
sudo crictl pods

# 3. Check static pod manifests and pod logs on disk
ls -la /etc/kubernetes/manifests/
sudo ls -la /var/log/pods/
sudo tail -n 50 /var/log/containers/kube-apiserver*.log

# 4. Check kubelet configuration and certificate expiration
sudo cat /var/lib/kubelet/config.yaml
sudo kubeadm certs check-expiration

# 5. Check disk space, swap, and network sockets
df -h
free -h
sudo ss -tulpn | grep -E '6443|2379|10250'
```
