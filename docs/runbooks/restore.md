# Restore

Bring back the `monitoring` namespace, with Prometheus's history, from a Velero backup. Played
on 2026-10-28: about three minutes.

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml
velero backup get
```

1. Suspend Argo CD, the root first, or it puts the child back:

   ```sh
   kubectl -n argocd patch application app-of-apps --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
   kubectl -n argocd patch application monitoring --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
   ```

2. If the namespace is gone: `make secrets`. The backups hold no Secret.

3. Restore, without cert-manager's requests, which would block it:

   ```sh
   velero restore create --from-backup <backup> --exclude-resources certificaterequests.cert-manager.io
   ```

   Do not delete any pod of `monitoring` until it ends: a new pod loses the container that waits
   for the data.

4. Resume Argo CD at once, the child first. It brings back the chart's Secrets, without which
   Prometheus never starts:

   ```sh
   kubectl -n argocd patch application monitoring --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true}}}}'
   kubectl -n argocd patch application app-of-apps --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true}}}}'
   ```

5. Check: `velero restore describe <restore>` shows `Completed`, and every `Application` is
   `Synced` and `Healthy`.
