# Domain 2: Workloads & Scheduling (15% of CKA)

[⬅ Back to Main CKA Hub](../Readme.md)

This module covers **15% of the CKA exam**. You will practice managing Deployments, DaemonSets, Static Pods, Node Scheduling (Taints, Tolerations, Node Affinity), ConfigMaps, Secrets, Probes, Multi-Container Pods, and Resource Metrics (`metrics-server`).

---

## Table of Contents
- [Lab 2.1: Deployments, Rolling Updates & Rollbacks](#lab-21-deployments-rolling-updates--rollbacks)
- [Lab 2.2: Static Pods & DaemonSets](#lab-22-static-pods--daemonsets)
- [Lab 2.3: Taints, Tolerations & Node Affinity](#lab-23-taints-tolerations--node-affinity)
- [Lab 2.4: ConfigMaps, Secrets, Probes, Init & Sidecar Containers](#lab-24-configmaps-secrets-probes-init--sidecar-containers)
- [Lab 2.5: Metrics Server, `kubectl top` & HorizontalPodAutoscaler (HPA)](#lab-25-metrics-server-kubectl-top--horizontalpodautoscaler-hpa)

---

## Lab 2.1: Deployments, Rolling Updates & Rollbacks

### Exam Scenario
> 1. Create a Deployment named `webapp` with image `nginx:1.24` and `4` replicas.
> 2. Perform a rolling update to `nginx:1.25` and record the rollout.
> 3. Simulate a bad rollout to `nginx:invalid-tag`, observe the failure, and roll back to the previous working revision.

<details>
<summary><b>Show solution</b> (try the scenario on your own first)</summary>

### Step-by-Step Lab

```bash
# 1. Create Deployment
kubectl create deployment webapp --image=nginx:1.24 --replicas=4

# 2. Update image to nginx:1.25 and watch rollout status
kubectl set image deployment/webapp nginx=nginx:1.25
kubectl rollout status deployment/webapp

# 3. Trigger a broken update
kubectl set image deployment/webapp nginx=nginx:invalid-tag
kubectl get pods -l app=webapp

# 4. Check rollout history and undo the bad rollout
kubectl rollout history deployment/webapp
kubectl rollout undo deployment/webapp
kubectl rollout status deployment/webapp

# Cleanup
kubectl delete deployment webapp
```

</details>

---

## Lab 2.2: Static Pods & DaemonSets

### Part A: Static Pods
Static pods are managed directly by `kubelet` on a specific node without the API server's scheduler. Their manifests live in `staticPodPath` (by default `/etc/kubernetes/manifests`).

> **kind path:** ⚠️ Generate the YAML on your WSL host, then write it into the node container: `kubectl run static-web --image=nginx:alpine --dry-run=client -o yaml | docker exec -i k8s-control-plane tee /etc/kubernetes/manifests/static-web.yaml`. The mirror pod is suffixed `-k8s-control-plane`. Remove it with `docker exec k8s-control-plane rm /etc/kubernetes/manifests/static-web.yaml`.

```bash
# 1. Find the staticPodPath configured for kubelet
sudo grep -i staticPodPath /var/lib/kubelet/config.yaml

# 2. Create a static pod manifest on k8s-master
kubectl run static-web --image=nginx:alpine --dry-run=client -o yaml | sudo tee /etc/kubernetes/manifests/static-web.yaml

# 3. Verify the mirror pod appears in kubectl (suffixed with -k8s-master)
kubectl get pods

# 4. Remove the static pod (deleting via kubectl won't work—you must delete the file!)
sudo rm /etc/kubernetes/manifests/static-web.yaml
```

### Part B: Creating a DaemonSet Quickly in the Exam
`kubectl create` does not have a `daemonset` subcommand! The fastest exam trick is to generate a `Deployment` YAML and change `kind: Deployment` to `kind: DaemonSet` (removing `replicas`, `strategy`, and `status`):

```bash
kubectl create deployment log-agent --image=busybox --dry-run=client -o yaml -- sleep 3600 > ds.yaml
```

Edit `ds.yaml` so it looks like this:
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-agent
spec:
  selector:
    matchLabels:
      app: log-agent
  template:
    metadata:
      labels:
        app: log-agent
    spec:
      containers:
      - name: busybox
        image: busybox
        args: ["sleep", "3600"]
```

```bash
kubectl apply -f ds.yaml
kubectl get ds log-agent
kubectl delete -f ds.yaml && rm ds.yaml
```

---

## Lab 2.3: Taints, Tolerations & Node Affinity

### Exam Scenario
> 1. Taint `k8s-worker` with `dedicated=gpu:NoSchedule` and label it `hardware=gpu`.
> 2. Create a pod named `gpu-pod` with a matching `toleration` and `nodeAffinity` (`requiredDuringSchedulingIgnoredDuringExecution`) using the `In` operator so it schedules on `k8s-worker`.

<details>
<summary><b>Show solution</b> (try the scenario on your own first)</summary>

### Step-by-Step Lab

1. **Apply a taint and label to `k8s-worker`:**
   ```bash
   kubectl taint nodes k8s-worker dedicated=gpu:NoSchedule
   kubectl label nodes k8s-worker hardware=gpu
   ```

2. **Deploy a pod with Toleration + `nodeAffinity`:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: gpu-pod
   spec:
     affinity:
       nodeAffinity:
         requiredDuringSchedulingIgnoredDuringExecution:
           nodeSelectorTerms:
           - matchExpressions:
             - key: hardware
               operator: In
               values:
               - gpu
               - tpu
     tolerations:
     - key: "dedicated"
       operator: "Equal"
       value: "gpu"
       effect: "NoSchedule"
     containers:
     - name: cuda-app
       image: nginx:alpine
   EOF
   ```

3. **Verify scheduling and clean up the taint:**
   ```bash
   kubectl get pod gpu-pod -o wide
   kubectl delete pod gpu-pod

   # Remove taint (note the trailing minus "-" sign!)
   kubectl taint nodes k8s-worker dedicated=gpu:NoSchedule-
   kubectl label nodes k8s-worker hardware-
   ```

</details>

---

## Lab 2.4: ConfigMaps, Secrets, Probes, Init & Sidecar Containers

### Exam Scenario
> Create a Pod named `app-with-sidecar`:
> - Mount a `Secret` named `db-secret` (`DB_PASS=s3cr3t`) as an environment variable.
> - Mount a `ConfigMap` named `app-cfg` (`app.conf=mode=production`) as a file inside `/etc/config`.
> - Run an `initContainer` (`init-setup`) that writes an initial line to a shared `emptyDir` volume `/var/log/nginx`.
> - Configure a `livenessProbe` and `readinessProbe` on port `80` of the main `nginx` container.
> - Run a `busybox` sidecar container that tails `/var/log/nginx/access.log`.

<details>
<summary><b>Show solution</b> (try the scenario on your own first)</summary>

### Step-by-Step Lab

```bash
# 1. Create Secret and ConfigMap imperatively
kubectl create secret generic db-secret --from-literal=DB_PASS=s3cr3t
kubectl create configmap app-cfg --from-literal=app.conf="mode=production"

# 2. Deploy the Pod with initContainer, Sidecar, Probes, Secret env, and ConfigMap volume
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: app-with-sidecar
spec:
  volumes:
  - name: shared-logs
    emptyDir: {}
  - name: config-vol
    configMap:
      name: app-cfg
  initContainers:
  - name: init-setup
    image: busybox:1.36
    command: ["/bin/sh", "-c", "echo 'Init completed' > /var/log/nginx/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  containers:
  - name: main-app
    image: nginx:alpine
    ports:
    - containerPort: 80
    env:
    - name: DATABASE_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-secret
          key: DB_PASS
    resources:
      requests:
        cpu: "50m"
        memory: "64Mi"
      limits:
        cpu: "100m"
        memory: "128Mi"
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 3
      periodSeconds: 5
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
    - name: config-vol
      mountPath: /etc/config
  - name: log-sidecar
    image: busybox:1.36
    command: ["/bin/sh", "-c", "tail -n+1 -F /var/log/nginx/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
EOF

# 3. Verify both containers (2/2 Ready), ConfigMap file, and sidecar logs
kubectl wait --for=condition=ready pod/app-with-sidecar --timeout=60s
kubectl exec app-with-sidecar -c main-app -- cat /etc/config/app.conf
kubectl exec app-with-sidecar -c main-app -- wget -qO- http://localhost
kubectl logs app-with-sidecar -c log-sidecar

# Cleanup
kubectl delete pod app-with-sidecar
kubectl delete secret db-secret
kubectl delete configmap app-cfg
```

</details>

---

## Lab 2.5: Metrics Server, `kubectl top` & HorizontalPodAutoscaler (HPA)

The CKA exam tests resource usage inspection (`kubectl top`) and configuring `HorizontalPodAutoscaler` (`HPA`). On a `kubeadm` homelab, `metrics-server` requires `--kubelet-insecure-tls` because `kubelet` uses self-signed certificates.

1. **Install `metrics-server` patched for `kubeadm` homelabs:**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

   # Patch metrics-server to allow self-signed kubelet certificates
   kubectl patch deployment metrics-server -n kube-system \
     --type='json' \
     -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
   ```

2. **Wait for `metrics-server` to become `1/1 Ready`, then test `kubectl top`:**
   ```bash
   kubectl rollout status deployment/metrics-server -n kube-system
   # The first scrape takes ~60s; until then "kubectl top" says "metrics not available yet"

   # View node CPU/Memory usage
   kubectl top nodes

   # Find the highest CPU-consuming pods across all namespaces
   kubectl top pods -A --sort-by=cpu
   kubectl top pods -A --sort-by=memory
   ```

3. **Create a HorizontalPodAutoscaler (`HPA`) imperatively:**
   ```bash
   # Create a deployment with CPU requests (required for HPA!)
   kubectl create deployment php-apache --image=registry.k8s.io/hpa-example
   kubectl set resources deployment php-apache --requests=cpu=200m

   # Create HPA targeting 50% CPU utilization (min 1, max 5 replicas)
   kubectl autoscale deployment php-apache --cpu-percent=50 --min=1 --max=5

   # Inspect the HPA
   kubectl get hpa php-apache

   # Cleanup
   kubectl delete hpa php-apache
   kubectl delete deployment php-apache
   ```


---

⬅ **Previous:** [Domain 1: Cluster Architecture](../01-cluster-architecture/README.md) · [⬆ CKA Study Hub](../Readme.md#cka-study-hub--hands-on-lab-modules) · **Next:** [Domain 3: Services & Networking](../03-services-networking/README.md) ➡
