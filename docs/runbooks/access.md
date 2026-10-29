# Access

The nodes, the cluster and its interfaces, after `make up`. Why through the bastion:
[ADR 3](../adr/0003-reach-the-nodes-through-a-bastion.md).

## Nodes

```sh
ssh -F .project/ssh/config volta-bastion
ssh -F .project/ssh/config volta-lab-server-1
```

`make ssh-config` writes the configuration and the known hosts. Never answer `yes` to an unknown
host key: the right ones are already in the file.

## Cluster

```sh
export KUBECONFIG=~/.kube/volta-lab.yaml
kubectl get nodes
```

Always set `KUBECONFIG`: the workstation's default context may be another cluster. If the tunnel
dropped (`connection refused`), `make kubeconfig` opens it again. To close it:
`pkill -f 'L 127.0.0.1:6443'`.

## Argo CD and Grafana

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
```

Argo CD on `https://localhost:8080`, user `admin`. Grafana on `http://localhost:3000`, user
`admin`, password in `~/.config/volta/grafana-admin-password`.

## Changing what runs

- Edit `cluster/`, open a pull request, merge: Argo CD applies it within three minutes.
- No `helm` or `kubectl apply` on what Argo CD manages; going back is a `git revert`.
- Argo CD itself: `make services`, after changing `cluster/argocd/values.yaml` or its version.
