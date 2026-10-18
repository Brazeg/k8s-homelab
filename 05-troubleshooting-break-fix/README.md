# Domain 5: Troubleshooting (30% of CKA) & Interactive Break-Fix Lab

[⬅ Back to Main CKA Hub](../Readme.md)

**Troubleshooting is the single largest domain on the CKA exam (30%).** Because you built a real multi-node `kubeadm` cluster on Ubuntu VMs, you can practice breaking and fixing the exact same components tested in the exam.

---

## 1. Systematic CKA Troubleshooting Flowchart

```mermaid
flowchart TD
    Start["🚨 Issue Reported in Exam"] --> Q1{"Does 'kubectl get nodes' work?"}
    Q1 -- "No (Connection Refused / Timeout)" --> CP["Control Plane Down"]
    CP --> CP1["1. Check kubelet & containerd:\nsystemctl status kubelet containerd"]
    CP1 --> CP2["2. Check Static Pod Manifests:\n/etc/kubernetes/manifests/*.yaml"]
    CP2 --> CP3["3. Inspect Container Logs:\ncrictl ps -a && crictl logs <id>\n/var/log/pods/"]

    Q1 -- "Yes" --> Q2{"Are all Nodes 'Ready'?"}
    Q2 -- "No (Node is NotReady)" --> WK["Worker Node / CNI Issue"]
    WK --> WK1["1. SSH to broken node:\nsystemctl status kubelet"]
    WK1 --> WK2["2. Read kubelet journal:\njournalctl -xeu kubelet"]
    WK2 --> WK3["3. Check swap, /var/lib/kubelet/config.yaml,\nor CNI pods in kube-system"]

    Q2 -- "Yes (All Nodes Ready)" --> Q3{"What is failing?"}
    Q3 -- "Pods Pending / CrashLoopBackOff" --> WL["Workload Issue"]
    WL --> WL1["Pending: kubectl describe pod\n(Taints, nodeSelector, PVC, CPU/Mem)"]
    WL1 --> WL2["CrashLoop: kubectl logs <pod> --previous\n(Bad command, missing Secret/ConfigMap, failing Probe)"]

    Q3 -- "Service / DNS Unreachable" --> NET["Networking Issue"]
    NET --> NET1["1. Check Service Endpoints:\nkubectl get ep <svc-name>\n(Mismatching Pod selector labels?)"]
    NET1 --> NET2["2. Check targetPort vs containerPort"]
    NET2 --> NET3["3. Check NetworkPolicies:\nkubectl get netpol -A"]
    NET3 --> NET4["4. Check CoreDNS pods in kube-system"]
```

---

## 2. Interactive "Break & Fix" Practice Scenarios

Each scenario folder contains:
- **`break.sh`**: Run this script to inject a realistic CKA exam failure into your cluster without peeking at what it changed.
- **`verify.sh`**: Run this script after you think you've fixed the issue—it grades your work (`PASS ✅` or `FAIL ❌`).
- **`SOLUTION.md`**: Step-by-step diagnosis and fix if you get stuck.

> **💡 Before You Start:** Make sure you have a clean VMware Snapshot of `k8s-master` and `k8s-worker`, or always run `verify.sh` before moving to the next scenario!

| Scenario | CKA Topic Tested | Where to Run `break.sh` | Difficulty |
| :--- | :--- | :--- | :--- |
| [**Scenario 01: Worker Node `NotReady`**](./scenario-01-worker-notready/SOLUTION.md) | `systemd`, `kubelet` config, node recovery | Run on **`k8s-worker`** | ⭐⭐ |
| [**Scenario 02: Control Plane API Server Down**](./scenario-02-apiserver-down/SOLUTION.md) | Static Pods (`/etc/kubernetes/manifests`), `crictl`, `etcd` port debugging | Run on **`k8s-master`** | ⭐⭐⭐ |
| [**Scenario 03: Service & NetworkPolicy Blackhole**](./scenario-03-network-blackhole/SOLUTION.md) | Service selectors, `Endpoints`, Calico `NetworkPolicy` | Run on **`k8s-master`** | ⭐⭐⭐ |
| [**Scenario 04: Stuck Workloads (`Pending` & `CrashLoopBackOff`)**](./scenario-04-pending-and-crashloop/SOLUTION.md) | Node scheduling (`nodeSelector`/Taints), container args, `livenessProbe` | Run on **`k8s-master`** | ⭐⭐ |

---

## 3. How to Run a Scenario

```bash
# Example: Running Scenario 02 on k8s-master
cd ~/k8s-homelab/05-troubleshooting-break-fix/scenario-02-apiserver-down

# 1. Break the cluster
chmod +x break.sh verify.sh
./break.sh

# 2. Diagnose and fix the issue using your CKA skills!

# 3. Grade your solution
./verify.sh
```

> **kind path:** ⚠️ Scenarios 03 and 04 run from your WSL terminal exactly as shown. Scenarios 01 and 02 break a node, so copy the scenario into the node container and run it there as root:
> ```bash
> # Scenario 01 (worker node)
> docker cp scenario-01-worker-notready k8s-worker:/root/
> docker exec -it -w /root/scenario-01-worker-notready k8s-worker bash   # then ./break.sh ... ./verify.sh
>
> # Scenario 02 (control plane). Inside the node, kubectl needs the admin kubeconfig
> docker cp scenario-02-apiserver-down k8s-control-plane:/root/
> docker exec -it -e KUBECONFIG=/etc/kubernetes/admin.conf -w /root/scenario-02-apiserver-down k8s-control-plane bash
> ```
> Snapshot equivalent: `kind delete cluster --name k8s` and then recreate it ([kind/README.md](../kind/README.md)).
