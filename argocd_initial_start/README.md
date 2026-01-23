# ARGO-CD installation

## Add the repo
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

## List the most recent chart
```bash
helm search repo argo-cd
```

## Install the most recent chart
```bash
k create ns argocd

helm install argo-cd argo/argo-cd --namespace argocd --values config.yaml
```

or

## Upgrade to the most recent version
```bash
helm upgrade --install argo-cd argo/argo-cd --version <CHART_VERSION> \
  --values config.yaml --namespace argocd --wait --timeout 900s
```

## Install master chart
```bash
cd k8s/master

helm template . | kubectl apply -f -
```