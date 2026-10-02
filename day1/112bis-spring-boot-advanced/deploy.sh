#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
#  deploy.sh — TD Spring Boot avancé : déploie ET teste chaque module 105 → 112
#
#  ./deploy.sh <module> [action]   module : 105 106 107 108 109 110 111 112 | all
#                                  action : deploy | test | clean   (vide = deploy puis test)
#  ./deploy.sh build               (re)construit les images dans le Docker de Minikube
#  ./deploy.sh status              vue d'ensemble des namespaces et releases
#
#  Variables : NS (namespace Helm, défaut spring-helm)  RELEASE (défaut demo)  TAG (défaut 1.0.0)
#              INGRESS_HOST (défaut spring-helm.local)  FORCE_BUILD=1
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$HERE/app"
CHART="$HERE/106-helm/spring-demo"
export NS="${NS:-spring-helm}"          # le 105 garde spring-demo (manifests bruts)
export RELEASE="${RELEASE:-demo}"
TAG="${TAG:-1.0.0}"
INGRESS_HOST="${INGRESS_HOST:-spring-helm.local}"
MON_NS=monitoring

# ── helpers ──────────────────────────────────────────────────────────────────
c_blue=$'\e[34m'; c_green=$'\e[32m'; c_red=$'\e[31m'; c_yel=$'\e[33m'; c_dim=$'\e[2m'; c_off=$'\e[0m'
step()  { printf '\n%s▶ %s%s\n' "$c_blue" "$*" "$c_off"; }
ok()    { printf '%s  ✅ %s%s\n' "$c_green" "$*" "$c_off"; }
warn()  { printf '%s  ⚠️  %s%s\n' "$c_yel" "$*" "$c_off"; }
fail()  { printf '%s  ❌ %s%s\n' "$c_red" "$*" "$c_off"; exit 1; }
run()   { printf '%s  $ %s%s\n' "$c_dim" "$*" "$c_off" >&2; "$@"; }
need()  { command -v "$1" >/dev/null || fail "outil manquant : $1 ($2)"; }

# Exécute une commande et vérifie que sa sortie contient un motif (regex étendue)
expect() { # expect "<description>" "<motif>" cmd...
  local desc=$1 pattern=$2; shift 2
  local out; out=$("$@" 2>&1) || true
  if grep -Eq -- "$pattern" <<<"$out"; then ok "$desc"; else printf '%s\n' "$out" | tail -5; fail "$desc (motif attendu : $pattern)"; fi
}

# Attend qu'une commande réussisse (timeout en secondes)
wait_for() { # wait_for <timeout> "<description>" cmd...
  local timeout=$1 desc=$2; shift 2
  local end=$((SECONDS + timeout))
  until "$@" >/dev/null 2>&1; do
    (( SECONDS < end )) || fail "timeout : $desc"
    sleep 3
  done
  ok "$desc"
}

has_netpol_cni() { kubectl -n kube-system get ds -o name 2>/dev/null | grep -Eq "calico|cilium"; }

rollout() { for d in "$@"; do run kubectl -n "$NS" rollout status deploy/"$d" --timeout=240s >/dev/null; done; }

# URL interne d'un Service de la release : svc order => http://demo-order.spring-helm:8080
svc() { echo "http://$RELEASE-$1.$NS:8080"; }

# curl depuis l'intérieur du cluster, lancé dans le namespace ingress-nginx : c'est le seul
# autorisé à entrer par les NetworkPolicies du 110, et il n'est pas soumis aux PSS du namespace appli.
kcurl() {
  kubectl -n ingress-nginx run "curl-$RANDOM" --rm -i --restart=Never -q --image=curlimages/curl:8.10.1 \
    --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"curl","image":"curlimages/curl:8.10.1","args":["-sS","--max-time","20",'"$(printf '"%s",' "$@" | sed 's/,$//')"'],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}' \
    -- "$@" 2>/dev/null | grep -v '^warning:' || true
}
export -f svc kcurl fail

# helm upgrade --install avec les values cumulées jusqu'au module demandé (109 → 112 s'empilent)
helm_apply() { # helm_apply <module>
  local m=$1 args=()
  args+=(--set "catalog.image.tag=$TAG" --set "order.image.tag=$TAG" --set "ingress.host=$INGRESS_HOST")
  if (( m >= 109 )) && kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then args+=(-f "$HERE/109-observability/values.yaml"); fi
  (( m >= 110 )) && args+=(-f "$HERE/110-security/values.yaml")
  (( m >= 111 )) && args+=(-f "$HERE/111-autoscaling/values.yaml")
  (( m >= 112 )) && args+=(-f "$HERE/112-storage/values.yaml")
  run helm upgrade --install "$RELEASE" "$CHART" -n "$NS" --create-namespace --wait --timeout 5m "${args[@]}" >/dev/null
}

tf() { if command -v terraform >/dev/null; then terraform "$@"; elif command -v tofu >/dev/null; then tofu "$@"; else fail "terraform ou tofu requis (brew install opentofu)"; fi; }
export -f tf

# ── prérequis & build ────────────────────────────────────────────────────────
prereqs() {
  step "Prérequis"
  need minikube "brew install minikube"; need kubectl "brew install kubectl"; need helm "brew install helm"; need docker "Docker Desktop"
  minikube status >/dev/null 2>&1 || fail "Minikube n'est pas démarré : minikube start --cpus 4 --memory 6g --cni=calico"
  ok "minikube $(kubectl version 2>/dev/null | grep Server)"
  minikube addons enable ingress >/dev/null 2>&1; minikube addons enable metrics-server >/dev/null 2>&1
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s >/dev/null
  ok "addons ingress + metrics-server"
}

build() {
  step "Build des images (dans le Docker de Minikube)"
  eval "$(minikube docker-env)"
  if [[ -z "${FORCE_BUILD:-}" ]] && docker image inspect "catalog-service:$TAG" "order-service:$TAG" >/dev/null 2>&1; then
    ok "images déjà présentes (FORCE_BUILD=1 pour reconstruire)"; return
  fi
  run docker build -q -t "catalog-service:$TAG" "$APP/catalog-service" >/dev/null
  run docker build -q -t "order-service:$TAG"   "$APP/order-service"   >/dev/null
  ok "catalog-service:$TAG, order-service:$TAG"
}

# ── 105 : manifests bruts ────────────────────────────────────────────────────
deploy_105() {
  step "105 — kubectl apply des manifests bruts (namespace spring-demo)"
  run kubectl apply -f "$APP/k8s/" >/dev/null
  NS=spring-demo rollout catalog order
}
test_105() {
  step "105 — tests"
  local ns=spring-demo
  kubectl -n $ns scale deploy/catalog --replicas=2 >/dev/null; NS=$ns rollout catalog order
  expect "catalog répond et lit la ConfigMap" '"environment":"kubernetes"' kubectl -n $ns exec deploy/order -- wget -qO- http://catalog:8080/api/products/whoami
  expect "order appelle catalog" '"productName":"Mug Helm"' kubectl -n $ns exec deploy/order -- wget -qO- --post-data='{"productId":2,"quantity":1}' --header='Content-Type: application/json' http://order:8080/api/orders
  run kubectl -n $ns scale deploy/catalog --replicas=0 >/dev/null
  wait_for 90 "catalog à 0 → order NotReady (readiness)" bash -c "[ -z \"\$(kubectl -n $ns get endpoints order -o jsonpath='{.subsets[*].addresses}')\" ]"
  expect "…mais pas redémarré (liveness OK)" '^0 0$' bash -c "kubectl -n $ns get pods -l app=order -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount} {end}' | sed 's/ $//'"
  run kubectl -n $ns scale deploy/catalog --replicas=2 >/dev/null
  NS=$ns rollout catalog
  wait_for 120 "catalog revenu → order Ready" bash -c "[ \$(kubectl -n $ns get endpoints order -o jsonpath='{.subsets[0].addresses}' | grep -o ip | wc -l) -ge 2 ]"
}
clean_105() { step "105 — nettoyage"; kubectl delete ns spring-demo --ignore-not-found --wait=false >/dev/null; ok "namespace spring-demo supprimé"; }

# ── 106 : Helm ───────────────────────────────────────────────────────────────
deploy_106() {
  step "106 — Helm : lint + install"
  run helm lint "$CHART" >/dev/null
  helm_apply 106
  ok "release $RELEASE installée dans $NS"
}
test_106() {
  step "106 — tests"
  expect "helm template rend 8 objets" '^8$' bash -c "helm template x '$CHART' | grep -c '^kind:'"
  kubectl -n "$NS" delete pod "$RELEASE-test-api" --ignore-not-found >/dev/null 2>&1   # reliquat d'un test précédent
  expect "helm test (Pod de test dans le cluster)" 'Phase:.*Succeeded' helm test "$RELEASE" -n "$NS" --timeout 3m
  run helm upgrade "$RELEASE" "$CHART" -n "$NS" --reuse-values --set catalog.env.CATALOG_ENVIRONMENT=upgraded --wait >/dev/null
  expect "upgrade propage la ConfigMap (checksum → rollout)" '"environment":"upgraded"' kcurl "$(svc catalog)/api/products/whoami"
  run helm rollback "$RELEASE" -n "$NS" --wait >/dev/null
  expect "rollback" '"environment":"helm"' kcurl "$(svc catalog)/api/products/whoami"
  expect "historique ≥ 3 révisions (install, upgrade, rollback)" '^(3|[4-9]|[1-9][0-9]+)$' bash -c "helm history $RELEASE -n $NS -o json | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))'"
}
clean_106() { step "106 — nettoyage"; helm uninstall "$RELEASE" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true; kubectl delete ns "$NS" --ignore-not-found --wait=false >/dev/null; ok "release + namespace $NS supprimés"; }

# ── 107 : Terraform ──────────────────────────────────────────────────────────
deploy_107() {
  step "107 — Terraform : namespace + helm_release"
  ( cd "$HERE/107-terraform" && run tf init -input=false >/dev/null && run tf apply -auto-approve -input=false >/dev/null )
  ok "tf apply (namespace spring-tf, release demo)"
}
test_107() {
  step "107 — tests"
  ( cd "$HERE/107-terraform"
    expect "state contient 2 ressources" '^2$' bash -c "tf state list | wc -l | tr -d ' '"
    expect "plan idempotent (No changes)" 'No changes' tf plan -input=false -detailed-exitcode
    expect "label PSS posé par Terraform" 'restricted' kubectl get ns spring-tf -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}'
    expect "variable environment → ConfigMap → app" '"environment":"terraform"' bash -c "NS=spring-tf kcurl \$(NS=spring-tf svc catalog)/api/products/whoami"
    run tf apply -auto-approve -input=false -var replicas=3 >/dev/null
    expect "tf apply -var replicas=3 scale les Deployments" '^3 3$' bash -c "kubectl -n spring-tf get deploy -o jsonpath='{range .items[*]}{.spec.replicas} {end}' | sed 's/ $//'"
  )
}
clean_107() { step "107 — nettoyage"; ( cd "$HERE/107-terraform" && { [ -f terraform.tfstate ] && tf destroy -auto-approve -input=false >/dev/null || true; }; rm -rf .terraform terraform.tfstate* .terraform.lock.hcl ); kubectl delete ns spring-tf --ignore-not-found --wait=false >/dev/null 2>&1 || true; ok "tf destroy"; }

# ── 108 : CI en local ────────────────────────────────────────────────────────
deploy_108() { step "108 — CI : rien à déployer (workflow .github/workflows/spring-demo.yml)"; ok "voir 108-cicd/README.md"; }
test_108() {
  step "108 — rejouer les jobs de la CI en local"
  for s in catalog-service order-service; do
    expect "mvn verify $s" 'BUILD SUCCESS' bash -c "cd '$APP/$s' && ./mvnw -B verify 2>&1 | tail -20"
  done
  expect "helm lint" '0 chart\(s\) failed' helm lint "$CHART"
  expect "helm template (toutes briques)" 'kind: StatefulSet' helm template ci "$CHART" -f "$HERE/109-observability/values.yaml" -f "$HERE/110-security/values.yaml" -f "$HERE/111-autoscaling/values.yaml" -f "$HERE/112-storage/values.yaml"
  ( cd "$HERE/107-terraform" && expect "terraform validate" 'valid' bash -c "tf init -backend=false -input=false >/dev/null && tf validate" )
  expect "workflow YAML valide" 'ok' python3 -c "import yaml; yaml.safe_load(open('$HERE/../../.github/workflows/spring-demo.yml')); print('ok')"
}
clean_108() { step "108 — nettoyage"; rm -rf "$APP"/*/target; ok "target/ supprimés"; }

# ── 109 : observabilité ──────────────────────────────────────────────────────
deploy_109() {
  step "109 — kube-prometheus-stack + ServiceMonitor + PrometheusRule + dashboard"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update prometheus-community >/dev/null
  run helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n $MON_NS --create-namespace \
      -f "$HERE/109-observability/kube-prometheus-stack-values.yaml" --wait --timeout 10m >/dev/null
  run kubectl apply -f "$HERE/109-observability/grafana-dashboard.yaml" >/dev/null
  helm_apply 109
  ok "stack monitoring + spring-demo instrumenté"
}
test_109() {
  step "109 — tests"
  expect "ServiceMonitor créé" "$RELEASE-spring-demo" kubectl -n "$NS" get servicemonitor -o name
  expect "/actuator/prometheus expose orders_placed_total" 'orders_placed_total' kcurl "$(svc order)/actuator/prometheus"
  for i in 1 2 3; do kcurl -X POST -H 'Content-Type: application/json' -d '{"productId":3,"quantity":1}' "$(svc order)/api/orders" >/dev/null; done
  local prom="http://monitoring-kube-prometheus-prometheus.$MON_NS:9090"
  wait_for 180 "Prometheus scrape les 2 services (targets up)" bash -c "kcurl '$prom/api/v1/query?query=up%7Bjob%3D~%22.*(catalog%7Corder)%22%7D' | grep -q '\"value\":\\[[0-9.]*,\"1\"\\]'"
  wait_for 120 "PromQL : sum(orders_placed_total) > 0" bash -c "kcurl '$prom/api/v1/query?query=sum(orders_placed_total%7Boutcome%3D%22success%22%7D)' | grep -Eq '\"value\":\\[[0-9.]*,\"[1-9]'"
  expect "règles d'alerte chargées" 'SpringDemoOrderNotReady' kcurl "$prom/api/v1/rules"
  expect "dashboard Grafana provisionné" 'spring-demo' kubectl -n $MON_NS get cm spring-demo-dashboard -o name
  printf '%s  ℹ️  Grafana : kubectl -n %s port-forward svc/monitoring-grafana 3000:80  (admin / admin)%s\n' "$c_dim" "$MON_NS" "$c_off"
}
clean_109() { step "109 — nettoyage"; helm uninstall monitoring -n $MON_NS --ignore-not-found >/dev/null 2>&1 || true; kubectl delete ns $MON_NS --ignore-not-found --wait=false >/dev/null; kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack-prometheus-operator --ignore-not-found >/dev/null 2>&1 || true; ok "monitoring supprimé"; }

# ── 110 : sécurité ───────────────────────────────────────────────────────────
deploy_110() {
  step "110 — PSS restricted, securityContext, NetworkPolicies, RBAC"
  run kubectl label ns "$NS" pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted --overwrite >/dev/null
  helm_apply 110
  run kubectl -n "$NS" apply -f "$HERE/110-security/rbac-readonly.yaml" >/dev/null
  ok "appli durcie"
}
test_110() {
  step "110 — tests"
  expect "Pods non-root (runAsUser 10001)" '^10001$' bash -c "kubectl -n $NS get pod -l app.kubernetes.io/name=order -o jsonpath='{.items[0].spec.securityContext.runAsUser}'"
  expect "rootfs en lecture seule" 'Read-only file system' kubectl -n "$NS" exec deploy/"$RELEASE"-order -- sh -c 'touch /app/x 2>&1'
  expect "PSS enforce=restricted refuse un Pod root" 'violates PodSecurity' kubectl -n "$NS" run bad --image=nginx --restart=Never --dry-run=server -o name
  expect "order → catalog autorisé" '"hostname"' kubectl -n "$NS" exec deploy/"$RELEASE"-order -- wget -qO- -T 5 "http://$RELEASE-catalog:8080/api/products/whoami"
  if has_netpol_cni; then
    expect "catalog → order interdit (NetworkPolicy)" 'timed out|can.t connect|Operation timed out' kubectl -n "$NS" exec deploy/"$RELEASE"-catalog -- sh -c "wget -qO- -T 5 http://$RELEASE-order:8080/api/orders 2>&1 || true"
  else warn "NetworkPolicies non appliquées par ce CNI (minikube start --cni=calico) : test d'isolation ignoré"; fi
  expect "RBAC : dev-readonly peut lister les pods" '^yes$' kubectl -n "$NS" auth can-i list pods --as=system:serviceaccount:$NS:dev-readonly
  expect "RBAC : dev-readonly ne peut pas lire les secrets" '^no$' bash -c "kubectl -n $NS auth can-i get secrets --as=system:serviceaccount:$NS:dev-readonly || true"
  expect "RBAC : dev-readonly ne peut pas supprimer" '^no$' bash -c "kubectl -n $NS auth can-i delete deployments --as=system:serviceaccount:$NS:dev-readonly || true"
  if command -v trivy >/dev/null; then
    if TAG=$TAG "$HERE/110-security/scan-images.sh" >/tmp/trivy.log 2>&1; then ok "trivy : aucune CVE HIGH/CRITICAL corrigeable"; else tail -15 /tmp/trivy.log; warn "trivy a trouvé des CVE (voir /tmp/trivy.log)"; fi
  else warn "trivy absent (brew install trivy) : scan ignoré"; fi
}
clean_110() { step "110 — nettoyage"; kubectl -n "$NS" delete -f "$HERE/110-security/rbac-readonly.yaml" --ignore-not-found >/dev/null 2>&1 || true; kubectl label ns "$NS" pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/warn- >/dev/null 2>&1 || true; helm_apply 109; ok "durcissement retiré"; }

# ── 111 : autoscaling ────────────────────────────────────────────────────────
deploy_111() {
  step "111 — HPA + PDB + metrics-server"
  helm_apply 111
  wait_for 120 "metrics-server renvoie des métriques" kubectl -n "$NS" top pods
}
test_111() {
  step "111 — tests (≈ 4 min : montée en charge puis redescente)"
  expect "HPA présent" "$RELEASE-catalog" kubectl -n "$NS" get hpa -o name
  expect "PDB présents" '^2$' bash -c "kubectl -n $NS get pdb -o name | wc -l | tr -d ' '"
  wait_for 90 "HPA lit le CPU (plus de <unknown>)" bash -c "kubectl -n $NS get hpa $RELEASE-catalog -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' | grep -Eq '^[0-9]+$'"
  run kubectl -n "$NS" delete job load-generator --ignore-not-found >/dev/null
  sed "s/demo-catalog/$RELEASE-catalog/" "$HERE/111-autoscaling/load-generator.yaml" | kubectl -n "$NS" apply -f - >/dev/null
  wait_for 240 "scale-up : catalog > 2 réplicas sous charge" bash -c "[ \$(kubectl -n $NS get deploy $RELEASE-catalog -o jsonpath='{.spec.replicas}') -gt 2 ]"
  kubectl -n "$NS" get hpa "$RELEASE-catalog"
  run kubectl -n "$NS" delete job load-generator --ignore-not-found >/dev/null
  wait_for 300 "scale-down : retour à 2 réplicas" bash -c "[ \$(kubectl -n $NS get deploy $RELEASE-catalog -o jsonpath='{.spec.replicas}') -eq 2 ]"
}
clean_111() { step "111 — nettoyage"; kubectl -n "$NS" delete job load-generator --ignore-not-found >/dev/null; helm_apply 110; ok "HPA/PDB retirés"; }

# ── 112 : stockage ───────────────────────────────────────────────────────────
deploy_112() {
  step "112 — PostgreSQL (StatefulSet + PVC) pour les commandes"
  helm_apply 112
  run kubectl -n "$NS" rollout status sts/"$RELEASE"-postgres --timeout=180s >/dev/null
  ok "order utilise PostgreSQL"
}
test_112() {
  step "112 — tests"
  expect "PVC Bound" 'Bound' kubectl -n "$NS" get pvc "data-$RELEASE-postgres-0" -o jsonpath='{.status.phase}'
  expect "readiness order inclut la base PostgreSQL" '"database":"PostgreSQL"' kcurl "$(svc order)/actuator/health/readiness"
  kcurl -X POST -H 'Content-Type: application/json' -d '{"productId":1,"quantity":1}' "$(svc order)/api/orders" >/dev/null
  local before; before=$(kcurl "$(svc order)/api/orders/whoami" | sed -E 's/.*"orders":([0-9]+).*/\1/')
  expect "les 2 Pods order voient les mêmes données (plus de H2 par Pod)" '"orders":'"$before" kcurl "$(svc order)/api/orders/whoami"
  run kubectl -n "$NS" delete pod "$RELEASE-postgres-0" --wait=false >/dev/null
  run kubectl -n "$NS" rollout status sts/"$RELEASE"-postgres --timeout=180s >/dev/null
  wait_for 120 "après suppression du Pod postgres : $before commande(s) toujours là" bash -c "kcurl $(svc order)/api/orders/whoami | grep -q '\"orders\":$before'"
  expect "même PVC réutilisé" 'Bound' kubectl -n "$NS" get pvc "data-$RELEASE-postgres-0" -o jsonpath='{.status.phase}'
}
clean_112() { step "112 — nettoyage"; helm_apply 111; kubectl -n "$NS" delete pvc "data-$RELEASE-postgres-0" --ignore-not-found >/dev/null; ok "PostgreSQL + PVC supprimés (retour à H2)"; }

# ── orchestration ────────────────────────────────────────────────────────────
status() {
  step "Status"
  for ns in spring-demo "$NS" spring-tf $MON_NS; do
    kubectl get ns "$ns" >/dev/null 2>&1 || continue
    printf '%s── namespace %s%s\n' "$c_dim" "$ns" "$c_off"
    kubectl -n "$ns" get deploy,sts,hpa,pdb,netpol,pvc 2>/dev/null | grep -v '^$' || true
  done
  helm list -A 2>/dev/null
}

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,2\}//'; exit 1; }

MODULES=(105 106 107 108 109 110 111 112)
main() {
  local target=${1:-} action=${2:-}
  case "$target" in
    build)  prereqs; FORCE_BUILD=1 build; exit ;;
    status) status; exit ;;
    all|105|106|107|108|109|110|111|112) ;;
    *) usage ;;
  esac
  [[ -z "$action" || "$action" =~ ^(deploy|test|clean)$ ]] || usage

  local list=("$target"); [[ $target == all ]] && list=("${MODULES[@]}")

  if [[ $action == clean ]]; then
    # dans l'ordre inverse : 112 → 105 (les values 109-112 se "dépilent"), 108 en dernier (fichiers locaux)
    [[ $target == all ]] && list=(112 111 110 109 107 106 105 108)
    for m in "${list[@]}"; do "clean_$m"; done
    exit
  fi

  prereqs; build
  # Les modules 109 → 112 s'appuient sur la release Helm du 106
  if [[ $target != all && $target -ge 109 ]] && ! helm status "$RELEASE" -n "$NS" >/dev/null 2>&1; then deploy_106; fi
  for m in "${list[@]}"; do
    [[ $action == test ]] || "deploy_$m"
    [[ $action == deploy ]] || "test_$m"
  done
  printf '\n%s🎉 Terminé : %s%s\n' "$c_green" "${list[*]}" "$c_off"
}
main "$@"
