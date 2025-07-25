{{/*
Common labels
*/}}
{{- define "trustid-issuer.vaultIssuerNode.common.labels" -}}
helm.sh/chart: {{ include "trustid-issuer.chart" . }}
{{ include "trustid-issuer.vaultIssuerNode.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Define custom deployment selectorLabels for vault
*/}}
{{- define "trustid-issuer.vaultIssuerNode.deploymentLabels" -}}
app: {{ .Values.vaultIssuerNode.deployment.labels.app }}
{{- end }}

{{/*
Define custom service selectorLabels for vault
*/}}
{{- define "trustid-issuer.vaultIssuerNode.Labels" -}}
app: {{ .Values.vaultIssuerNode.service.selector }}
{{- end }}

{{- define "trustid-issuer.vaultIssuerNode.staticLabel" -}}
app: {{ .Values.vaultIssuerNode.labels.app }}
{{- end }}

{{- define "trustid-issuer.vaultIssuerNode.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}

{{- define "helpers.serviceAccountName" -}}
{{- printf "%s-%s%s" .Release.Name .Release.Namespace "-service-account" -}}
{{- end -}}
