# Domain 3: Services & Networking (20% of CKA)

[⬅ Back to Main CKA Hub](../Readme.md)

This module covers **20% of the CKA exam**. Because your homelab uses **Calico CNI** on multi-node VMs, you can practice every single CKA networking topic natively—including Services, CoreDNS debugging, Ingress, the new **Gateway API**, and **NetworkPolicies**.

---

## Table of Contents
- [Lab 3.1: Services (`ClusterIP`, `NodePort`) & CoreDNS Resolution](#lab-31-services-clusterip-nodeport--coredns-resolution)
- [Lab 3.2: Ingress Controller & Routing Rules](#lab-32-ingress-controller--routing-rules)
- [Lab 3.3: Gateway API (`GatewayClass`, `Gateway`, `HTTPRoute`)](#lab-33-gateway-api-gatewayclass-gateway-httproute)
- [Lab 3.4: NetworkPolicies with Calico](#lab-34-networkpolicies-with-calico)

---

## Lab 3.1: Services (`ClusterIP`, `NodePort`) & CoreDNS Resolution

### Understanding Kubernetes DNS FQDN Format
Every Service and Pod gets a DNS record in CoreDNS:
- **Service FQDN:** `<service-name>.<namespace>.svc.cluster.local`
- **Pod FQDN:** `<pod-ip-with-dashes>.<namespace>.pod.cluster.local` (e.g., `172-16-135-10.default.pod.cluster.local`)

### Step-by-Step Lab

```bash
# 1. Create a deployment and expose it as a ClusterIP service
kubectl create deployment api-backend --image=nginx:alpine --replicas=2
kubectl expose deployment api-backend --name=api-svc --port=8080 --target-port=80

# 2. Verify Service and Endpoints
kubectl get svc api-svc
kubectl get endpoints api-svc

# 3. Test DNS resolution and HTTP connectivity using a temporary busybox pod
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- sh -c \
  "nslookup api-svc.default.svc.cluster.local && wget -qO- http://api-svc.default.svc.cluster.local:8080"

# Cleanup
kubectl delete deploy api-backend && kubectl delete svc api-svc
```

---

## Lab 3.2: Ingress Controller & Routing Rules

> **⚠️ ingress-nginx is retired.** Kubernetes SIG Network announced its retirement in November 2025. Maintenance ended in March 2026 and the repository is now archived, so it gets no more releases or security fixes. The `Ingress` API itself is still part of Kubernetes and the CKA, so this lab still teaches the resource. For new work, prefer the **Gateway API** ([Lab 3.3](#lab-33-gateway-api-gatewayclass-gateway-httproute)).

### Step-by-Step Lab

1. **Install the NGINX Ingress Controller (bare-metal NodePort manifest) and pin its HTTP NodePort to `30081`:**
   ```bash
   # controller-v1.13.9 supports Kubernetes 1.29–1.33 (VM path).
   # On the kind path (Kubernetes 1.35), use controller-v1.15.1 instead.
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.9/deploy/static/provider/baremetal/deploy.yaml
   kubectl wait --namespace ingress-nginx \
     --for=condition=ready pod \
     --selector=app.kubernetes.io/component=controller \
     --timeout=120s

   # A fixed port is easier to remember (and kind maps 30081 to localhost)
   kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' \
     -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30081}]'
   ```

2. **Create two backend services (`video-svc` and `shop-svc`):**
   ```bash
   kubectl create deployment video-app --image=hashicorp/http-echo -- /http-echo -text="Welcome to Video Service"
   kubectl expose deployment video-app --name=video-svc --port=5678

   kubectl create deployment shop-app --image=hashicorp/http-echo -- /http-echo -text="Welcome to Shop Service"
   kubectl expose deployment shop-app --name=shop-svc --port=5678
   ```

3. **Create an `Ingress` resource routing `/video` and `/shop`:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: networking.k8s.io/v1
   kind: Ingress
   metadata:
     name: app-ingress
   spec:
     ingressClassName: nginx
     rules:
     - host: homelab.local
       http:
         paths:
         - path: /video
           pathType: Prefix
           backend:
             service:
               name: video-svc
               port:
                 number: 5678
         - path: /shop
           pathType: Prefix
           backend:
             service:
               name: shop-svc
               port:
                 number: 5678
   EOF
   ```

4. **Test the Ingress via the Ingress Controller's `NodePort`:**
   ```bash
   INGRESS_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
   curl -H "Host: homelab.local" http://192.168.56.20:$INGRESS_PORT/video
   curl -H "Host: homelab.local" http://192.168.56.20:$INGRESS_PORT/shop
   # kind path: replace 192.168.56.20 with localhost

   # Cleanup
   kubectl delete ingress app-ingress
   kubectl delete deploy video-app shop-app
   kubectl delete svc video-svc shop-svc
   ```

---

## Lab 3.3: Gateway API (`GatewayClass`, `Gateway`, `HTTPRoute`)

> **🔥 Important 2025/2026 CKA Update:** The CKA curriculum now explicitly tests the **Kubernetes Gateway API** (`gateway.networking.k8s.io/v1`), which is the modern successor to `Ingress`.

### Core Gateway API Resources
1. **`GatewayClass`**: Defines the controller implementation (cluster-scoped, similar to `IngressClass`).
2. **`Gateway`**: Defines the network endpoint / listener (ports, protocols, hostnames, TLS).
3. **`HTTPRoute`**: Attaches to a `Gateway` via `parentRefs` and routes HTTP traffic (`matches` → `backendRefs`).

### Practice Manifests

1. **Install the official Gateway API CRDs:**
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.0/standard-install.yaml
   ```

> **Schema-only lab:** the `GatewayClass` below names a placeholder controller (`example.io/gateway-controller`), and no Gateway implementation is installed. The API server **accepts** all three objects, but nothing programs them, so no traffic is routed. That matches how the CKA tests Gateway API: writing correct `Gateway`/`HTTPRoute` YAML and reading its `status`.

2. **Create a backend, then `GatewayClass`, `Gateway`, and `HTTPRoute` (Official `gateway.networking.k8s.io/v1` Pattern):**
   ```bash
   kubectl create deployment api-backend --image=nginx:alpine
   kubectl expose deployment api-backend --name=api-svc --port=8080 --target-port=80

   cat <<EOF | kubectl apply -f -
   apiVersion: gateway.networking.k8s.io/v1
   kind: GatewayClass
   metadata:
     name: nginx-class
   spec:
     controllerName: example.io/gateway-controller
   ---
   apiVersion: gateway.networking.k8s.io/v1
   kind: Gateway
   metadata:
     name: web-gateway
     namespace: default
   spec:
     gatewayClassName: nginx-class
     listeners:
     - name: http
       protocol: HTTP
       port: 80
       hostname: "app.example.com"
       allowedRoutes:
         namespaces:
           from: Same
   ---
   apiVersion: gateway.networking.k8s.io/v1
   kind: HTTPRoute
   metadata:
     name: web-route
     namespace: default
   spec:
     parentRefs:
     - name: web-gateway
       sectionName: http
     hostnames:
     - "app.example.com"
     rules:
     - matches:
       - path:
           type: PathPrefix
           value: /api
       backendRefs:
       - name: api-svc
         port: 8080
   EOF
   ```

3. **Inspect what the API stored and its status:**
   ```bash
   kubectl get gatewayclass,gateway,httproute
   # With no controller, the conditions stay "Unknown" (e.g. Accepted: Unknown, "Waiting for controller")
   kubectl get gateway web-gateway -o jsonpath='{.status.conditions}{"\n"}'
   kubectl explain httproute.spec.rules.matches

   # Cleanup
   kubectl delete httproute web-route && kubectl delete gateway web-gateway && kubectl delete gatewayclass nginx-class
   kubectl delete deploy api-backend && kubectl delete svc api-svc
   ```

---

## Lab 3.4: NetworkPolicies with Calico

### Exam Scenario
> In namespace `netpol-demo`, three pods run: `frontend`, `backend`, and `db`.
> Create a `NetworkPolicy` named `restrict-db` in `netpol-demo` that:
> - Applies to `role=db` pods.
> - Allows **Ingress** traffic on TCP port `3306` (or `80` for testing) **ONLY** from pods labeled `role=backend` in the same namespace.
> - Blocks all other ingress traffic to `db`.

<details>
<summary><b>Show solution</b> (try the scenario on your own first)</summary>

### Step-by-Step Lab

1. **Create the namespace, pods, and service:**
   ```bash
   kubectl create namespace netpol-demo
   kubectl run db -n netpol-demo --image=nginx:alpine -l role=db --expose --port=80
   kubectl run backend -n netpol-demo --image=busybox:1.36 -l role=backend -- sleep 3600
   kubectl run frontend -n netpol-demo --image=busybox:1.36 -l role=frontend -- sleep 3600
   kubectl wait --for=condition=ready pod --all -n netpol-demo --timeout=60s
   ```

2. **Apply the `NetworkPolicy`:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: restrict-db
     namespace: netpol-demo
   spec:
     podSelector:
       matchLabels:
         role: db
     policyTypes:
     - Ingress
     ingress:
     - from:
       - podSelector:
           matchLabels:
             role: backend
       ports:
       - protocol: TCP
         port: 80
   EOF
   ```

3. **Test connectivity from `backend` (Allowed) vs. `frontend` (Blocked):**
   ```bash
   # Should SUCCEED (prints nginx HTML)
   kubectl exec -n netpol-demo backend -- wget -qO- --timeout=3 http://db

   # Should TIMED OUT / FAIL (blocked by Calico NetworkPolicy!)
   kubectl exec -n netpol-demo frontend -- wget -qO- --timeout=3 http://db

   # Cleanup
   kubectl delete namespace netpol-demo
   ```

</details>

> **💡 Exam Tip 1 (`AND` vs `OR` in NetworkPolicy):**
> ```yaml
> # ONE list item with both namespaceSelector and podSelector = AND (must match both)
> - from:
>   - namespaceSelector:
>       matchLabels:
>         env: prod
>     podSelector:
>       matchLabels:
>         role: backend
>
> # TWO separate list items (two dashes "-") = OR (matches either)
> - from:
>   - namespaceSelector:
>       matchLabels:
>         env: prod
>   - podSelector:
>       matchLabels:
>         role: backend
> ```
>
> **💡 Exam Tip 2 (Allowing DNS Port 53 in `Egress` NetworkPolicies):**
> Whenever you write a `NetworkPolicy` that restricts `Egress`, always remember to allow `UDP` and `TCP` port `53` so the Pod can still resolve service names via CoreDNS:
> ```yaml
>   egress:
>   - to:
>     - namespaceSelector:
>         matchLabels:
>           kubernetes.io/metadata.name: kube-system
>       podSelector:
>         matchLabels:
>           k8s-app: kube-dns
>     ports:
>     - protocol: UDP
>       port: 53
>     - protocol: TCP
>       port: 53
> ```


---

⬅ **Previous:** [Domain 2: Workloads & Scheduling](../02-workloads-scheduling/README.md) · [⬆ CKA Study Hub](../Readme.md#cka-study-hub--hands-on-lab-modules) · **Next:** [Domain 4: Storage](../04-storage/README.md) ➡
