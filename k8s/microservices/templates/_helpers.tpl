{{- define "microservices.imageRepo" -}}
{{- default (printf "%s.dkr.ecr.%s.amazonaws.com/%s" .Values.awsAccountNumber (.Values.awsRegion | default "us-east-2") .Values.environment) .Values.ecrRepo -}}
{{- end -}}

{{- define "microservices.s3volume" }}
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: {{ .parentName }}-{{ .volName }}-s3-pv
  annotations:
    argocd.argoproj.io/sync-options: Replace=true
spec:
  capacity:
    storage: 1200Gi
  accessModes:
    {{- if .vol.readOnly }}
    - ReadOnlyMany
    {{- else }}
    - ReadWriteMany
    {{- end }}
  storageClassName: ""
  mountOptions:
    - allow-other
    - region {{ .awsRegion }}
    {{- if .vol.uid }}
    - uid={{ .vol.uid }}
    {{- end }}
    {{- if .vol.gid }}
    - gid={{ .vol.gid }}
    {{- end }}
    {{- if .vol.readOnly }}
    - read-only
    {{- end }}
  csi:
    driver: s3.csi.aws.com
    volumeHandle: {{ .parentName }}-{{ .volName }}-s3
    volumeAttributes:
      bucketName: {{ tpl .vol.bucketName .root }}
      authenticationSource: driver
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .parentName }}-{{ .volName }}-s3-pvc
  namespace: {{ .namespace }}
spec:
  accessModes:
    {{- if .vol.readOnly }}
    - ReadOnlyMany
    {{- else }}
    - ReadWriteMany
    {{- end }}
  storageClassName: ""
  resources:
    requests:
      storage: 1200Gi
  volumeName: {{ .parentName }}-{{ .volName }}-s3-pv
{{- end }}
