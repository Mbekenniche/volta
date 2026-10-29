# Restore

How to bring back the `monitoring` namespace, with Prometheus's history, from a Velero backup.
Played on 2026-10-28 on the running cluster, after deleting the namespace and its volume. Why it
works this way is recorded in [ADR 0019](../adr/0019-back-up-to-swift-with-velero.md).

## What it takes

- The `velero` CLI, and the cluster's kubeconfig and tunnel, as in the
  [cluster access runbook](cluster-access.md).
- A backup. One is taken every day at 03:00 UTC and kept seven days:

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml
velero backup get
```

## 1. Suspend Argo CD

```sh
kubectl -n argocd patch application app-of-apps --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
kubectl -n argocd patch application monitoring --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":false}}}}'
```

- **Velero never replaces an object that exists**, and Argo CD recreates within seconds what is
  missing, with an empty volume that Velero would then keep.
- **The root first.** Left running, it would put its child's policy back.

## 2. The namespace's Secret

The backup holds no Secret. If the namespace is gone, `make secrets` creates it again, with
Grafana's admin password ([lifecycle runbook](lifecycle.md)).

## 3. Restore

```sh
velero restore create --from-backup <backup> --exclude-resources certificaterequests.cert-manager.io
kubectl -n monitoring get pods,pvc
```

- **The claim is expected `Bound`, and Prometheus's pod in `Init`.** Velero adds an init container
  that waits for the data. Delete no pod of the namespace during the restore: a pod created again
  has no such container, and its volume stays empty.
- **cert-manager's requests stay out.** Restored, they point at a private key held in a Secret that
  is not there, stay pending, and block cert-manager.

## 4. Resume Argo CD, at once

```sh
kubectl -n argocd patch application monitoring --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true}}}}'
kubectl -n argocd patch application app-of-apps --type merge -p '{"spec":{"syncPolicy":{"automated":{"enabled":true}}}}'
```

- **The claim and the pod exist by now**, so Argo CD cannot recreate them empty.
- **Argo CD brings back the chart's Secrets**, which the backup excludes, Prometheus's scrape
  configuration among them. Without them, the operator generates no configuration and Prometheus
  never starts.
- **`kubectl apply -f cluster/argocd/root.yaml` does not resume the root**: it leaves in place a
  field the file does not mention.

## 5. Check

```sh
kubectl -n velero get podvolumerestores
velero restore describe <restore>
```

Every volume restore is expected `Completed`, then the restore itself. Prometheus then answers for
a time before the loss, and every `Application` is `Synced` and `Healthy`. On 2026-10-28, the
restore took about three minutes, the 3.88 GB volume about 86 s.
