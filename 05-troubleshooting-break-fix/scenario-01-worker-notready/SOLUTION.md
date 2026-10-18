# Scenario 01 Solution: Worker Node `NotReady`

[⬅ Back to Troubleshooting Hub](../README.md)

## Exam Prompt
> Worker node `k8s-worker` is in a `NotReady` state. Investigate the root cause on `k8s-worker` and restore it to `Ready`. Ensure the fix persists across reboots.

---

## Step-by-Step Diagnosis & Fix

1. **Check node status from `k8s-master`:**
   ```bash
   kubectl get nodes
   ```

2. **SSH into `k8s-worker` and check the `kubelet` systemd service:**
   ```bash
   ssh username@192.168.56.21
   sudo systemctl status kubelet
   ```
   You will notice `kubelet` is in an `activating (auto-restart)` crash loop (`status=1/FAILURE`).

3. **Inspect the `kubelet` logs using `journalctl`:**
   ```bash
   sudo journalctl -xeu kubelet --no-pager | tail -n 30
   ```
   Look at the error message:
   ```text
   unable to load client CA file /etc/kubernetes/pki/ca-missing.crt: open /etc/kubernetes/pki/ca-missing.crt: no such file or directory
   ```

4. **Fix `/var/lib/kubelet/config.yaml`:**
   Open `/var/lib/kubelet/config.yaml` and change `/etc/kubernetes/pki/ca-missing.crt` back to `/etc/kubernetes/pki/ca.crt`:
   ```bash
   sudo sed -i 's|/etc/kubernetes/pki/ca-missing.crt|/etc/kubernetes/pki/ca.crt|g' /var/lib/kubelet/config.yaml
   ```

5. **Restart `kubelet` and verify:**
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl restart kubelet
   sudo systemctl status kubelet
   ./verify.sh
   ```
