{{/*
Expand the name of the chart.
*/}}
{{- define "postgresql-ha.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "postgresql-ha.fullname" -}}
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
{{- define "postgresql-ha.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "postgresql-ha.labels" -}}
helm.sh/chart: {{ include "postgresql-ha.chart" . }}
{{ include "postgresql-ha.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "postgresql-ha.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql-ha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
PostgreSQL primary selector labels.
*/}}
{{- define "postgresql-ha.primarySelectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql-ha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: primary
{{- end }}

{{/*
PostgreSQL replica selector labels.
*/}}
{{- define "postgresql-ha.replicaSelectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql-ha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: replica
{{- end }}

{{/*
PgBouncer selector labels.
*/}}
{{- define "postgresql-ha.pgbouncerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql-ha.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: pgbouncer
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "postgresql-ha.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "postgresql-ha.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
PostgreSQL credentials secret name.
*/}}
{{- define "postgresql-ha.secretName" -}}
{{- if .Values.postgresql.auth.existingSecret }}
{{- .Values.postgresql.auth.existingSecret }}
{{- else }}
{{- include "postgresql-ha.fullname" . }}-credentials
{{- end }}
{{- end }}
