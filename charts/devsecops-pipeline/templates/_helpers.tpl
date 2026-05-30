{{/*
Expand the name of the chart.
*/}}
{{- define "devsecops-pipeline.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "devsecops-pipeline.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "devsecops-pipeline.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "devsecops-pipeline.labels" -}}
helm.sh/chart: {{ include "devsecops-pipeline.chart" . }}
{{ include "devsecops-pipeline.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "devsecops-pipeline.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devsecops-pipeline.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "devsecops-pipeline.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "devsecops-pipeline.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Runner token secret name — uses existingSecret if set, otherwise creates one.
*/}}
{{- define "devsecops-pipeline.runnerSecretName" -}}
{{- if .Values.gitlab.runner.existingSecret }}
{{- .Values.gitlab.runner.existingSecret }}
{{- else }}
{{- include "devsecops-pipeline.fullname" . }}-runner-token
{{- end }}
{{- end }}
