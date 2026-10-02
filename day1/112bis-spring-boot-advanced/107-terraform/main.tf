# ── 1. Le namespace, avec les labels Pod Security Standards (module 110) ──────
resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by"     = "terraform"
      "pod-security.kubernetes.io/warn"  = "restricted"
      "pod-security.kubernetes.io/audit" = "restricted"
    }
  }
}

# ── 2. La release Helm du chart local du module 106 ──────────────────────────
resource "helm_release" "spring_demo" {
  name      = var.release_name
  namespace = kubernetes_namespace_v1.app.metadata[0].name
  chart     = "${path.module}/../106-helm/spring-demo"

  atomic          = true # rollback automatique si les pods ne deviennent pas prêts
  wait            = true
  timeout         = 300
  cleanup_on_fail = true

  set {
    name  = "catalog.env.CATALOG_ENVIRONMENT"
    value = var.environment
  }
  set {
    name  = "catalog.replicaCount"
    value = var.replicas
  }
  set {
    name  = "order.replicaCount"
    value = var.replicas
  }
  set {
    name  = "catalog.image.tag"
    value = var.image_tag
  }
  set {
    name  = "order.image.tag"
    value = var.image_tag
  }
  set {
    name  = "ingress.host"
    value = var.ingress_host
  }
}
