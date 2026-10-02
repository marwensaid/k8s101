{{/*
Nom complet : <release>-<composant>, ex. demo-catalog
*/}}
{{- define "spring-demo.fullname" -}}
{{- printf "%s-%s" .root.Release.Name .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Labels communs (recommandations kubernetes.io)
*/}}
{{- define "spring-demo.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/part-of: spring-demo
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}

{{/*
Labels de sélection (ne doivent JAMAIS changer entre deux upgrades)
*/}}
{{- define "spring-demo.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/*
Tag d'image : valeur explicite, sinon appVersion du chart
*/}}
{{- define "spring-demo.image" -}}
{{- printf "%s:%s" .svc.image.repository (.svc.image.tag | default .root.Chart.AppVersion) -}}
{{- end -}}

{{/*
securityContext du Pod et du conteneur (module 110), activé par security.hardened
*/}}
{{- define "spring-demo.podSecurityContext" -}}
{{- if .Values.security.hardened }}
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
{{- end }}
{{- end -}}

{{- define "spring-demo.containerSecurityContext" -}}
{{- if .Values.security.hardened }}
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
{{- end }}
{{- end -}}

{{/*
Deployment + Service d'un composant Spring Boot.
Appelé avec : (dict "root" . "name" "catalog" "svc" .Values.catalog)
*/}}
{{- define "spring-demo.component" -}}
{{- $fullname := include "spring-demo.fullname" . -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "spring-demo.labels" . | nindent 4 }}
spec:
  {{- if not .svc.autoscaling.enabled }}
  replicas: {{ .svc.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "spring-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "spring-demo.selectorLabels" . | nindent 8 }}
      annotations:
        # Force un rollout quand la ConfigMap change (sinon les Pods gardent l'ancien env)
        checksum/config: {{ toYaml .svc.env | sha256sum }}
    spec:
      {{- if .root.Values.security.serviceAccount.create }}
      serviceAccountName: {{ .root.Release.Name }}-spring-demo
      automountServiceAccountToken: false
      {{- end }}
      {{- include "spring-demo.podSecurityContext" .root | nindent 6 }}
      containers:
        - name: {{ .name }}
          image: {{ include "spring-demo.image" . }}
          imagePullPolicy: {{ .root.Values.image.pullPolicy }}
          {{- include "spring-demo.containerSecurityContext" .root | nindent 10 }}
          ports:
            - name: http
              containerPort: 8080
          envFrom:
            - configMapRef:
                name: {{ $fullname }}
          {{- if and (eq .name "order") .root.Values.postgres.enabled }}
          env:
            - name: SPRING_DATASOURCE_USERNAME
              valueFrom:
                secretKeyRef: { name: {{ .root.Release.Name }}-postgres, key: POSTGRES_USER }
            - name: SPRING_DATASOURCE_PASSWORD
              valueFrom:
                secretKeyRef: { name: {{ .root.Release.Name }}-postgres, key: POSTGRES_PASSWORD }
          {{- end }}
          resources:
            {{- toYaml .svc.resources | nindent 12 }}
          {{- if .root.Values.security.hardened }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp          # la JVM a besoin d'un /tmp inscriptible
          {{- end }}
          startupProbe:
            httpGet: { path: /actuator/health/liveness, port: http }
            periodSeconds: 2
            failureThreshold: {{ .root.Values.probes.startupFailureThreshold }}
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: http }
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: http }
            periodSeconds: 5
      {{- if .root.Values.security.hardened }}
      volumes:
        - name: tmp
          emptyDir: {}
      {{- end }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "spring-demo.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "spring-demo.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: 8080
      targetPort: http
{{- end -}}
