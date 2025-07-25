{{/*
Common labels
*/}}
{{- define "trustid-issuer.postgresIssuerNode.common.labels" -}}
helm.sh/chart: {{ include "trustid-issuer.chart" . }}
{{ include "trustid-issuer.postgresIssuerNode.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "trustid-issuer.postgresIssuerNode.staticLabel" -}}
app: {{ .Values.postgresIssuerNode.labels.app }}
{{- end }}

{{- define "trustid-issuer.postgresIssuerNode.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}

{{/*
Define custom deployment selectorLabels for postgres
*/}}
{{- define "trustid-issuer.postgresIssuerNode.deploymentLabels" -}}
app: {{ .Values.postgresIssuerNode.deployment.labels.app }}
{{- end }}


{{/*
Define custom service selectorLabels for postgres
*/}}
{{- define "trustid-issuer.postgresIssuerNode.Labels" -}}
app: {{ .Values.postgresIssuerNode.service.selector }}
{{- end }}
