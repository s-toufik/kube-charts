{{/* ConfigMap holding configFiles.<name> */}}
{{- define "app.configMapName" -}}
{{- printf "%s-%s" (include "homelab.name" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* PVC behind persistence.<name>: its own claim for a Deployment, the first pod's for a StatefulSet */}}
{{- define "app.claimName" -}}
{{- if eq .root.Values.kind "StatefulSet" -}}
{{- printf "data-%s-%s-0" .name (include "homelab.name" .root) -}}
{{- else -}}
{{- printf "%s-%s" (include "homelab.name" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* Restarts the pods when a config file changes */}}
{{- define "app.configChecksum" -}}
{{- toYaml (.Values.configFiles | default dict) | sha256sum -}}
{{- end -}}

{{- define "app.serviceAccountName" -}}
{{- if or .Values.rbac.rules .Values.rbac.clusterRules -}}
{{- include "homelab.name" . -}}
{{- end -}}
{{- end -}}

{{/*
One container.
  root:          the chart root ($)
  name:          container name
  spec:          dict with image, command, args, env, secretEnv, resources, securityContext,
                 ports, probes, workingDir
  configFiles:   names of .Values.configFiles to mount
  persistence:   names of .Values.persistence to mount
  volumeMounts:  extra raw volumeMounts
*/}}
{{- define "app.container" -}}
{{- $root := .root -}}
{{- $c := .spec -}}
{{- $image := $c.image | default $root.Values.image -}}
{{- $env := deepCopy ($c.env | default dict) -}}
{{- if and $root.Values.global.timezone (not (hasKey $env "TZ")) -}}
{{- $_ := set $env "TZ" $root.Values.global.timezone -}}
{{- end -}}
- name: {{ .name }}
  image: {{ include "homelab.image" (dict "root" $root "image" $image) | quote }}
  imagePullPolicy: {{ $image.pullPolicy | default "IfNotPresent" }}
  {{- with $c.command }}
  command:
    {{- include "homelab.tpl" (dict "value" . "root" $root) | nindent 4 }}
  {{- end }}
  {{- with $c.args }}
  args:
    {{- include "homelab.tpl" (dict "value" . "root" $root) | nindent 4 }}
  {{- end }}
  {{- with $c.workingDir }}
  workingDir: {{ . | quote }}
  {{- end }}
  {{- $envList := include "homelab.env" (dict "env" $env "secretEnv" $c.secretEnv "root" $root) }}
  {{- if $envList }}
  env:
    {{- $envList | trim | nindent 4 }}
  {{- end }}
  {{- with $c.ports }}
  ports:
    {{- range . }}
    - name: {{ .name }}
      containerPort: {{ .port }}
      protocol: {{ .protocol | default "TCP" }}
      {{- if .hostPort }}
      hostPort: {{ .hostPort }}
      hostIP: {{ required "global.hostIP (the Tailscale address) is required to publish a hostPort" $root.Values.global.hostIP | quote }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- with $c.probes }}
  {{- with .startup }}
  startupProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .readiness }}
  readinessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .liveness }}
  livenessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
  {{- with $c.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  securityContext:
    {{- include "homelab.securityContext" (dict "securityContext" $c.securityContext) | nindent 4 }}
  {{- $mounts := list }}
  {{- range $name := .configFiles }}
  {{- $file := index $root.Values.configFiles $name | default dict }}
  {{- $mounts = append $mounts (dict "name" (printf "config-%s" $name) "mountPath" (required (printf "configFiles.%s.mountPath is required" $name) $file.mountPath) "readOnly" true) }}
  {{- end }}
  {{- range $name := .persistence }}
  {{- $volume := index $root.Values.persistence $name | default dict }}
  {{- $mount := dict "name" (printf "data-%s" $name) "mountPath" (required (printf "persistence.%s.mountPath is required" $name) $volume.mountPath) }}
  {{- with $volume.subPath }}{{ $_ := set $mount "subPath" . }}{{ end }}
  {{- $mounts = append $mounts $mount }}
  {{- end }}
  {{- $mounts = concat $mounts (.volumeMounts | default list) }}
  {{- with $mounts }}
  volumeMounts:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}

{{/*
Pod volumes for the given configFiles and persistence names, plus extra raw volumes.
StatefulSet pods get their persistence from volumeClaimTemplates instead (claimTemplates: true).
*/}}
{{- define "app.volumes" -}}
{{- $root := .root -}}
{{- $volumes := list -}}
{{- range $name := .configFiles -}}
{{- $volumes = append $volumes (dict "name" (printf "config-%s" $name) "configMap" (dict "name" (include "app.configMapName" (dict "root" $root "name" $name)))) -}}
{{- end -}}
{{- if not .claimTemplates -}}
{{- range $name := .persistence -}}
{{- $volumes = append $volumes (dict "name" (printf "data-%s" $name) "persistentVolumeClaim" (dict "claimName" (include "app.claimName" (dict "root" $root "name" $name)))) -}}
{{- end -}}
{{- end -}}
{{- $volumes = concat $volumes (.extra | default list) -}}
{{- with $volumes -}}
volumes:
  {{- include "homelab.tpl" (dict "value" . "root" $root) | nindent 2 }}
{{- end -}}
{{- end -}}

{{/* Pod-level settings shared by the workload, jobs and cron jobs */}}
{{- define "app.podSettings" -}}
{{- $root := . -}}
{{- $serviceAccount := include "app.serviceAccountName" . -}}
{{- if $serviceAccount }}
serviceAccountName: {{ $serviceAccount }}
automountServiceAccountToken: true
{{- else }}
automountServiceAccountToken: {{ .Values.serviceAccount.automount | default false }}
{{- end }}
# No <SERVICE>_PORT / _SERVICE_HOST variables: some images read every variable with their prefix
enableServiceLinks: {{ .Values.enableServiceLinks }}
{{- if .Values.hostNetwork }}
# The server's own network; Service names still resolve through the cluster's DNS
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet
{{- end }}
securityContext:
  {{- include "homelab.podSecurityContext" (dict "podSecurityContext" .Values.podSecurityContext) | nindent 2 }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
