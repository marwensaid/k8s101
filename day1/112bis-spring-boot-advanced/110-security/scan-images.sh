#!/usr/bin/env bash
# Module 110 : scan des images avec trivy (brew install trivy).
# Échoue (exit 1) s'il reste des CVE HIGH/CRITICAL pour lesquelles un correctif existe.
set -euo pipefail
TAG="${TAG:-1.0.0}"
eval "$(minikube docker-env)"      # scanner les images buildées dans Minikube
for img in "catalog-service:$TAG" "order-service:$TAG"; do
  echo "🔍 $img"
  trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --scanners vuln "$img"
done
