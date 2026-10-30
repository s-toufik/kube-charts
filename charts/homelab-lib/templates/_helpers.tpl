{{/*
Resource name: the release name, so a release "caddy" gives the Deployment, Service and
ConfigMaps "caddy" and other pods reach it at caddy:<port>.
*/}}
{{- define "homelab.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "homelab.selectorLabels" -}}
app.kubernetes.io/name: {{ include "homelab.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "homelab.labels" -}}
{{ include "homelab.selectorLabels" . }}
app.kubernetes.io/version: {{ include "homelab.imageTag" . | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: homelab
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Image tag: image.tag, else the chart's appVersion (the version CI published) */}}
{{- define "homelab.imageTag" -}}
{{- $image := .Values.image | default dict -}}
{{- $image.tag | default .Chart.AppVersion | toString -}}
{{- end -}}

{{/* "repository:tag" for the main image, or for an image dict passed as .image */}}
{{- define "homelab.image" -}}
{{- $image := .image | default .root.Values.image -}}
{{- $repository := required "image.repository is required" $image.repository -}}
{{- $tag := $image.tag | default .root.Chart.AppVersion | toString -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}

{{/*
Renders a value through `tpl`, so values files can use {{ .Values.global.domain }}.
Usage: include "homelab.tpl" (dict "value" $v "root" $)
*/}}
{{- define "homelab.tpl" -}}
{{- if kindIs "string" .value -}}
{{- tpl .value .root -}}
{{- else -}}
{{- tpl (toYaml .value) .root -}}
{{- end -}}
{{- end -}}

{{/*
Container env from two maps, sorted by name:
  env:       NAME: value                          (plain text, rendered with tpl)
  secretEnv: NAME: { secret: <name>, key: <key> }  (read from a Secret)
Secrets are listed first, so plain values can use $(SECRET_NAME) to build connection strings.
Usage: include "homelab.env" (dict "env" $env "secretEnv" $secretEnv "root" $)
*/}}
{{- define "homelab.env" -}}
{{- $root := .root -}}
{{- range $name := keys (.secretEnv | default dict) | sortAlpha }}
{{- $ref := index $.secretEnv $name }}
- name: {{ $name }}
  valueFrom:
    secretKeyRef:
      name: {{ required (printf "secretEnv.%s.secret is required" $name) $ref.secret | quote }}
      key: {{ required (printf "secretEnv.%s.key is required" $name) $ref.key | quote }}
      {{- if $ref.optional }}
      optional: true
      {{- end }}
{{- end }}
{{- range $name := keys (.env | default dict) | sortAlpha }}
{{- $value := index $.env $name }}
- name: {{ $name }}
  value: {{ if kindIs "invalid" $value }}""{{ else }}{{ include "homelab.tpl" (dict "value" (toString $value) "root" $root) | quote }}{{ end }}
{{- end }}
{{- end -}}

{{/* Pod security context: RuntimeDefault seccomp, merged with the values' podSecurityContext */}}
{{- define "homelab.podSecurityContext" -}}
{{- $defaults := dict "seccompProfile" (dict "type" "RuntimeDefault") -}}
{{- toYaml (mergeOverwrite $defaults (deepCopy (.podSecurityContext | default dict))) -}}
{{- end -}}

{{/* Container security context: no privilege escalation, no capabilities, merged with the values */}}
{{- define "homelab.securityContext" -}}
{{- $defaults := dict "allowPrivilegeEscalation" false "capabilities" (dict "drop" (list "ALL")) -}}
{{- toYaml (mergeOverwrite $defaults (deepCopy (.securityContext | default dict))) -}}
{{- end -}}
