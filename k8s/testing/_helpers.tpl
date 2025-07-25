
{{/*
Expand the name of the chart.
*/}}
{{- define "trustid-issuer.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "trustid-issuer.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}



{{/*
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "trustid-issuer.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "trustid-issuer.labels" -}}
helm.sh/chart: {{ include "trustid-issuer.chart" . }}
{{ include "trustid-issuer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "trustid-issuer.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
{{- end }}


{{/*
Define a static label 
*/}}
{{- define "trustid-issuer.staticLabel" -}}
app: {{ .Values.apiIssuerNode.service.labels.app }}
{{- end }}



{{/*
Define api server url
*/}}
{{- define "helpers.api-server-url" -}}
https://{{ .Values.apidomain }}/{{ .Release.Namespace }}
{{- end }}

{{/*
Define block explorer
*/}}
{{- define "helpers.issuer-block-explorer" -}}
{{- if eq .Values.mainnet true }}
{{ .Values.uiIssuerNode.configMap.issuerUiBlockExplorerUrlMain }}
{{- else }}
{{ .Values.uiIssuerNode.configMap.issuerUiBlockExplorerUrlAmoy }}
{{- end }}
{{- end }}

{{/*
Define an env var
*/}}
{{- define "helpers.issuer-db-url" -}}
ISSUER_DATABASE_URL
{{- end }}

{{/*
Define an env var
*/}}
{{- define "helpers.issuer-key-store-addr" -}}
ISSUER_KEY_STORE_ADDRESS
{{- end }}

{{/*
Define custom service selectorLabels for apiIssuerNode
*/}}
{{- define "trustid-issuer.apiIssuerNode.Labels" -}}
app: {{ .Values.apiIssuerNode.service.selector }}
{{- end }}

{{/*
Define custom deployment labels fors apiIssuerNode
*/}}
{{- define "trustid-issuer.apiIssuerNode.deploymentLabels" -}}
app: {{ .Values.apiIssuerNode.deployment.labels.app }}
{{- end }}

{{/*
Define custom service selectorLabels for apiUiIssuerNode
*/}}
{{- define "trustid-issuer.apiUiIssuerNode.Labels" -}}
app: {{ .Values.apiUiIssuerNode.service.selector }}
{{- end }}

{{/*
Define custom deployment selectorLabels for apiUiIssuerNode
*/}}
{{- define "trustid-issuer.apiUiIssuerNode.deploymentLabels" -}}
app: {{ .Values.apiUiIssuerNode.deployment.labels.app }}
{{- end }}


{{/*
Define custom deployment selectorLabels for notifications
*/}}
{{- define "trustid-issuer.notificationsIssuerNode.Labels" -}}
app: {{ .Values.notificationsIssuerNode.deployment.name }}
{{- end }}

{{/*
Define custom deployment label for notifications
*/}}
{{- define "trustid-issuer.notificationsIssuerNode.deploymentLabels" -}}
app: {{ .Values.notificationsIssuerNode.deployment.labels.app }}
{{- end }}

{{/*
Define custom deployment selectorLabels for pending-publisher
*/}}
{{- define "trustid-issuer.pendingPublisherIssuerNode.Labels" -}}
app: {{ .Values.pendingPublisherIssuerNode.deployment.name }}
{{- end }}

{{/*
Define custom deployment label for pending-publisher
*/}}
{{- define "trustid-issuer.pendingPublisherIssuerNode.deploymentLabels" -}}
app: {{ .Values.pendingPublisherIssuerNode.deployment.labels.app }}
{{- end }}


{{/*
Define custom service selectorLabels for UiIssuerNode
*/}}
{{- define "trustid-issuer.uiIssuerNode.Labels" -}}
app: {{ .Values.uiIssuerNode.service.selector }}
{{- end }}


{{/*
Define custom deployment selectorLabels for UiIssuerNode
*/}}
{{- define "trustid-issuer.uiIssuerNode.deploymentLabels" -}}
app: {{ .Values.uiIssuerNode.deployment.labels.app }}
{{- end }}

{{/*
Define custom service selectorLabels for postgres
*/}}
{{- define "trustid-issuer.postgresIssuerNode.Labels" -}}
app: {{ .Values.postgresIssuerNode.service.selector }}
{{- end }}


{{/*
Define custom deployment selectorLabels for postgres
*/}}
{{- define "trustid-issuer.postgresIssuerNode.deploymentLabels" -}}
app: {{ .Values.postgresIssuerNode.deployment.labels.app }}
{{- end }}


{{/*
Define custom service selectorLabels for redis
*/}}
{{- define "trustid-issuer.redisIssuerNode.Labels" -}}
app: {{ .Values.redisIssuerNode.service.selector }}
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



{{- define "helpers.serviceAccountName" -}}
{{- printf "%s-%s%s" .Release.Name .Release.Namespace "-service-account" -}}
{{- end -}}