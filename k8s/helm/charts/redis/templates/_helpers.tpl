{{/*
Common labels
*/}}
{{- define "trustid-issuer.redisIssuerNode.common.labels" -}}
helm.sh/chart: {{ include "trustid-issuer.chart" . }}
{{ include "trustid-issuer.redisIssuerNode.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define custom service selectorLabels for redis
*/}}
{{- define "trustid-issuer.redisIssuerNode.Labels" -}}
app: {{ .Values.redisIssuerNode.service.selector }}
{{- end }}

{{- define "trustid-issuer.redisIssuerNode.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}

{{- define "trustid-issuer.redisIssuerNode.staticLabel" -}}
app: {{ .Values.redisIssuerNode.labels.app }}
{{- end }}