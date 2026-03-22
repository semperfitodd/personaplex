{{- define "devops.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
  retry:
    limit: 2
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m0s
{{- end -}}
