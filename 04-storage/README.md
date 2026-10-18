# Domain 4: Storage (10% of CKA)

[⬅ Back to Main CKA Hub](../Readme.md)

This module covers **10% of the CKA exam**. You will configure PersistentVolumes (`PV`), PersistentVolumeClaims (`PVC`), `StorageClass` dynamic provisioning, and Pod volume mounts.

---

## Table of Contents
- [Lab 4.1: Static Provisioning (`PV` → `PVC` → `Pod`)](#lab-41-static-provisioning-pv--pvc--pod)
- [Lab 4.2: Dynamic Provisioning with `StorageClass` (`local-path-provisioner`)](#lab-42-dynamic-provisioning-with-storageclass-local-path-provisioner)
- [Lab 4.3: Expanding a `PersistentVolumeClaim` (`allowVolumeExpansion`)](#lab-43-expanding-a-persistentvolumeclaim-allowvolumeexpansion)

---

## Lab 4.1: Static Provisioning (`PV` → `PVC` → `Pod`)

### Exam Scenario
> 1. Create a `PersistentVolume` named `app-pv` with capacity `2Gi`, access mode `ReadWriteOnce`, `storageClassName: manual`, reclaim policy `Retain`, and `hostPath` `/mnt/app-data`.
> 2. Create a `PersistentVolumeClaim` named `app-pvc` requesting `1Gi` with `storageClassName: manual`. Verify it binds to `app-pv`.
> 3. Create a Pod named `storage-pod` (image `nginx:alpine`) that mounts `app-pvc` at `/usr/share/nginx/html`.

### Step-by-Step Lab

1. **Create the `PersistentVolume` and `PersistentVolumeClaim`:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolume
   metadata:
     name: app-pv
   spec:
     capacity:
       storage: 2Gi
     volumeMode: Filesystem
     accessModes:
       - ReadWriteOnce
     persistentVolumeReclaimPolicy: Retain
     storageClassName: manual
     hostPath:
       path: /mnt/app-data
       type: DirectoryOrCreate
   ---
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: app-pvc
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 1Gi
     storageClassName: manual
   EOF
   ```

2. **Verify `STATUS` is `Bound`:**
   ```bash
   kubectl get pv,pvc
   ```

3. **Mount the `PVC` inside `storage-pod`:**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: Pod
   metadata:
     name: storage-pod
   spec:
     containers:
     - name: nginx
       image: nginx:alpine
       volumeMounts:
       - name: html-storage
         mountPath: /usr/share/nginx/html
     volumes:
     - name: html-storage
       persistentVolumeClaim:
         claimName: app-pvc
   EOF
   ```

4. **Test persistence and clean up:**
   ```bash
   kubectl wait --for=condition=ready pod/storage-pod --timeout=60s
   kubectl exec storage-pod -- sh -c "echo 'Hello from Persistent Volume!' > /usr/share/nginx/html/index.html"
   kubectl exec storage-pod -- cat /usr/share/nginx/html/index.html

   # Cleanup
   kubectl delete pod storage-pod
   kubectl delete pvc app-pvc
   kubectl delete pv app-pv
   ```

---

## Lab 4.2: Dynamic Provisioning with `StorageClass` (`local-path-provisioner`)

In bare-metal or VMware homelab clusters, Kubernetes does not include a built-in dynamic storage provisioner by default. Installing Rancher's **Local Path Provisioner** gives your cluster a real dynamic `StorageClass` (just like in the CKA exam!).

> **kind path:** ⚠️ kind already runs `local-path-provisioner`, with a default StorageClass named `standard`. Skip steps 1–2 (re-applying the manifest would overwrite kind's copy), run step 3 as-is, and in Lab 4.3 patch `standard` instead of `local-path`.

1. **Install Rancher Local Path Provisioner:**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.28/deploy/local-path-storage.yaml
   ```

2. **Mark `local-path` as the default `StorageClass` (Common CKA Question!):**
   ```bash
   kubectl patch storageclass local-path \
     -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

   kubectl get storageclass
   # Notice "(default)" next to local-path!
   ```

3. **Test dynamic provisioning (`WaitForFirstConsumer` binding mode):**
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: dynamic-pvc
   spec:
     accessModes:
       - ReadWriteOnce
     resources:
       requests:
         storage: 500Mi
   ---
   apiVersion: v1
   kind: Pod
   metadata:
     name: dynamic-consumer
   spec:
     containers:
     - name: busybox
       image: busybox:1.36
       command: ["sh", "-c", "echo 'Dynamic PV works!' > /data/test.txt && sleep 3600"]
       volumeMounts:
       - name: data-vol
         mountPath: /data
     volumes:
     - name: data-vol
       persistentVolumeClaim:
         claimName: dynamic-pvc
   EOF
   ```

4. **Verify automatic PV creation:**
   ```bash
   kubectl wait --for=condition=ready pod/dynamic-consumer --timeout=60s
   kubectl get pvc dynamic-pvc
   kubectl get pv
   ```

---

## Lab 4.3: Expanding a `PersistentVolumeClaim` (`allowVolumeExpansion`)

### Exam Scenario
> Enable volume expansion on the `local-path` `StorageClass` and request a resize of `dynamic-pvc` from `500Mi` to `1Gi` without recreating the Pod.

> **⚠️ What actually happens in this homelab:** `local-path-provisioner` is hostPath-based and has **no resizer**, so it can't grow volumes. The API accepts your new request (`spec.resources.requests.storage: 1Gi`), but the volume's real size (`status.capacity.storage`) stays at `500Mi`. On the exam, the cluster's `StorageClass` uses a CSI driver with a resizer, so the same two commands complete the resize. The skill being tested is the commands plus knowing where to check the result.

```bash
# 1. Enable allowVolumeExpansion on the StorageClass (without it, the PVC patch is rejected)
kubectl patch storageclass local-path -p '{"allowVolumeExpansion": true}'

# 2. Patch (or kubectl edit) the PVC storage request from 500Mi to 1Gi
kubectl patch pvc dynamic-pvc -p '{"spec":{"resources":{"requests":{"storage":"1Gi"}}}}'

# 3. Compare what you asked for with what you got
kubectl get pvc dynamic-pvc -o jsonpath='requested={.spec.resources.requests.storage} actual={.status.capacity.storage}{"\n"}'
# Expected here: requested=1Gi actual=500Mi  (with a CSI resizer, actual would become 1Gi)
kubectl describe pvc dynamic-pvc   # check Conditions/Events for resize progress

# 4. Cleanup
kubectl delete pod dynamic-consumer
kubectl delete pvc dynamic-pvc
```

