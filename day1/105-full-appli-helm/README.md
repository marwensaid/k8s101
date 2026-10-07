# Helm chart — 105 Application complète

Ce chart reprend l'application Kubernetes du TD 105 :
- Namespace `demo-app`
- ConfigMap + Secret
- PostgreSQL + PVC + Service
- Backend + Service
- Frontend + Service
- Ingress

La structure et les valeurs par défaut reprennent les manifests du TD 105.

## Installation

```bash
helm install demo-app ./105-full-appli-helm
```

Le chart crée par défaut le namespace `demo-app`.

## Vérifier

```bash
kubectl get all,cm,secret,pvc,ingress -n demo-app
kubectl get pods -n demo-app -w
```

## Upgrade

```bash
helm upgrade demo-app ./105-full-appli-helm
```

## Désinstallation

```bash
helm uninstall demo-app
kubectl delete namespace demo-app
```

## Tester le rendu avant installation

```bash
helm template demo-app ./105-full-appli-helm
```

## Changer les valeurs

Exemple :

```bash
helm upgrade --install demo-app ./105-full-appli-helm   --set backend.replicas=4   --set frontend.replicas=3   --set ingress.host=demo.test
```

Ou avec un fichier :

```bash
helm upgrade --install demo-app ./105-full-appli-helm -f values-dev.yaml
```

## Minikube / Ingress

Comme dans le TD :

```bash
minikube addons enable ingress
```

Puis adapter `/etc/hosts` selon le mode Minikube utilisé.

> Attention : le Secret contient volontairement le mot de passe du TD en clair pour rester pédagogique. En production, utiliser par exemple Sealed Secrets, External Secrets ou Vault.
