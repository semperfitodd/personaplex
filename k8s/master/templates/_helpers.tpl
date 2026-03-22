{{- define "master.application" }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .project }}-{{ .environment }}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: {{ .project }}
  source:
    path: {{ .path }}
    repoURL: {{ .repoUrl }}
    targetRevision: HEAD
    helm:
      valueFiles:
        - values.yaml
      values: |- {{ toYaml .values | nindent 8 }}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
  {{- toYaml .syncPolicy | nindent 4 }}
{{- end -}}
