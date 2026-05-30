{{/*
Expand the name of the chart.
*/}}
{{- define "eks-autoscaler.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "eks-autoscaler.fullname" -}}
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
{{- define "eks-autoscaler.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource.
*/}}
{{- define "eks-autoscaler.labels" -}}
helm.sh/chart: {{ include "eks-autoscaler.chart" . }}
{{ include "eks-autoscaler.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
*/}}
{{- define "eks-autoscaler.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eks-autoscaler.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "eks-autoscaler.serviceAccountName" -}}
{{- include "eks-autoscaler.fullname" . }}
{{- end }}

{{/*
Validate required Karpenter values.
*/}}
{{- define "eks-autoscaler.validateRequired" -}}
{{- if not .Values.karpenter.clusterName }}
{{- fail "karpenter.clusterName is required — set it to your EKS cluster name" }}
{{- end }}
{{- if not .Values.ec2NodeClass.role }}
{{- fail "ec2NodeClass.role is required — set it to the EC2 node IAM role name" }}
{{- end }}
{{- end }}
