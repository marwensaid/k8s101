variable "kubeconfig" {
  description = "Chemin du kubeconfig"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Contexte kubectl à utiliser"
  type        = string
  default     = "minikube"
}

variable "namespace" {
  description = "Namespace créé par Terraform pour la release"
  type        = string
  default     = "spring-tf"
}

variable "release_name" {
  description = "Nom de la release Helm (préfixe des Services : <release>-catalog, <release>-order)"
  type        = string
  default     = "demo"
}

variable "environment" {
  description = "Injecté dans CATALOG_ENVIRONMENT → visible sur /api/products/whoami"
  type        = string
  default     = "terraform"
}

variable "replicas" {
  description = "Nombre de réplicas de chaque service"
  type        = number
  default     = 2
  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10
    error_message = "replicas doit être compris entre 1 et 10."
  }
}

variable "image_tag" {
  description = "Tag des images catalog-service / order-service (vide = appVersion du chart)"
  type        = string
  default     = "1.0.0"
}

variable "ingress_host" {
  description = "Hôte de l'Ingress (doit être unique dans le cluster)"
  type        = string
  default     = "spring-tf.local"
}
