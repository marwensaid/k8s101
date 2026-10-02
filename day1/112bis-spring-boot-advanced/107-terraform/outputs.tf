output "namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "release" {
  value = "${helm_release.spring_demo.name} (révision ${helm_release.spring_demo.version}, statut ${helm_release.spring_demo.status})"
}

output "catalog_url" {
  description = "URL interne du catalogue"
  value       = "http://${var.release_name}-catalog.${var.namespace}:8080/api/products"
}

output "order_url" {
  description = "URL interne des commandes"
  value       = "http://${var.release_name}-order.${var.namespace}:8080/api/orders"
}
