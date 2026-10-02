# ☕ Le code : `catalog-service` + `order-service`

Deux micro-services **Spring Boot 3.5 / Java 21** volontairement petits, mais équipés de tout ce
qu'une application attend de Kubernetes (et inversement). Ils sont utilisés par le
[TD 112bis](../README.md) du module 106 au module 112.

```
app/
├── catalog-service/        expose le catalogue
├── order-service/          passe des commandes en appelant le catalogue
├── docker-compose.yaml     les deux ensemble, en local
└── k8s/                    manifests Kubernetes bruts (namespace spring-demo)
```

Chaque service est un projet Maven autonome : `pom.xml`, Maven wrapper (`./mvnw`), `Dockerfile`,
`.dockerignore`, `src/main`, `src/test`.

---

## catalog-service

| Méthode | Chemin | Réponse |
|---------|--------|---------|
| `GET` | `/api/products` | les 4 produits : `[{"id":1,"name":"Casquette Kubernetes","price":19.90,"stock":42}, …]` |
| `GET` | `/api/products/{id}` | un produit, ou `404` |
| `GET` | `/api/products/whoami` | `{"hostname":"<pod>","environment":"<CATALOG_ENVIRONMENT>"}` — pour voir **quel Pod** répond et **quelle config** il a reçue |
| `GET` | `/actuator/health/liveness` · `/readiness` | probes |
| `GET` | `/actuator/prometheus` | métriques |

```
src/main/java/fr/k8s101/catalog/
├── CatalogApplication.java     @SpringBootApplication
├── Product.java                record (id, name, price, stock)
└── ProductController.java      liste en mémoire + endpoints
src/main/resources/application.yaml
src/test/java/fr/k8s101/catalog/ProductControllerTest.java   @WebMvcTest
```

| Variable d'env | Défaut | Effet |
|----------------|--------|-------|
| `CATALOG_ENVIRONMENT` | `local` | valeur renvoyée par `/whoami` (fournie par ConfigMap dans K8s) |

---

## order-service

| Méthode | Chemin | Réponse |
|---------|--------|---------|
| `POST` | `/api/orders` body `{"productId":2,"quantity":1}` | `201` `{"id":1,"productId":2,"productName":"Mug Helm","quantity":1,"total":12.50,"createdAt":…}` |
| | | `400` quantité ≤ 0 · `422` produit inconnu · `409` stock insuffisant · `503` catalogue injoignable |
| `GET` | `/api/orders` | toutes les commandes |
| `GET` | `/api/orders/{id}` | une commande, ou `404` |
| `GET` | `/api/orders/whoami` | `{"hostname":"<pod>","orders":<nombre de commandes vues par CE Pod>}` |
| `GET` | `/actuator/health/readiness` | `UP` seulement si `catalog` **et** `db` sont `UP` |
| `GET` | `/actuator/prometheus` | métriques, dont `orders_placed_total{outcome="success|rejected"}` |

```
src/main/java/fr/k8s101/order/
├── OrderApplication.java
├── CatalogClient.java            RestClient vers ${catalog.url} : findProduct(id), ping()
├── CatalogHealthIndicator.java   @Component("catalog") → contribue à la readiness
├── Order.java                    @Entity, table "orders"
├── OrderRepository.java          JpaRepository<Order, Long>
└── OrderController.java          validation via le catalogue, persistance, compteurs Micrometer
src/main/resources/application.yaml
src/test/java/fr/k8s101/order/OrderControllerTest.java   @WebMvcTest + @MockitoBean (CatalogClient, OrderRepository)
```

| Variable d'env | Défaut | Effet |
|----------------|--------|-------|
| `CATALOG_URL` | `http://localhost:8080` | URL du catalogue (`http://catalog:8080` dans K8s) |
| `SPRING_DATASOURCE_URL` | `jdbc:h2:mem:orders` | H2 en mémoire ; `jdbc:postgresql://host:5432/db` pour PostgreSQL (module 112) |
| `SPRING_DATASOURCE_USERNAME` / `PASSWORD` | `sa` / vide | identifiants de la base |

### Pourquoi la readiness dépend du catalogue

```java
@Component("catalog")
public class CatalogHealthIndicator implements HealthIndicator {
    public Health health() {
        try { client.ping(); return Health.up().build(); }
        catch (Exception e) { return Health.down().withDetail("catalog", e.getMessage()).build(); }
    }
}
```

```yaml
management.endpoint.health.group.readiness.include: readinessState,catalog,db
```

Catalogue ou base injoignable → `/actuator/health/readiness` = `503 DOWN` → Kubernetes **retire le Pod du
Service** (plus de trafic) mais **ne le redémarre pas** (la liveness reste `UP`). Dès que la dépendance
revient, le Pod reprend le trafic. C'est le comportement correct pour une panne *externe*.

### H2 ou PostgreSQL ?

Le `pom.xml` embarque les deux drivers (`runtime`). Spring Boot choisit selon `SPRING_DATASOURCE_URL`,
`ddl-auto: update` crée la table. Résultat : le **même jar** tourne en local sans rien installer, et sur
PostgreSQL en production — sans recompilation.

---

## Lancer en local

```bash
# 1. Deux terminaux, deux JVM
cd catalog-service && ./mvnw spring-boot:run
cd order-service   && SERVER_PORT=8081 ./mvnw spring-boot:run

curl -s localhost:8081/api/orders -X POST -H 'Content-Type: application/json' -d '{"productId":2,"quantity":1}'

# 2. Ou avec Docker Compose (healthcheck + dépendance ordonnée)
docker compose up --build
curl -s localhost:8082/api/orders -X POST -H 'Content-Type: application/json' -d '{"productId":2,"quantity":1}'
docker compose down
```

## Tester

```bash
cd catalog-service && ./mvnw -B verify
cd order-service   && ./mvnw -B verify
```

Les tests sont des `@WebMvcTest` : pas de base, pas de réseau — `CatalogClient` et `OrderRepository` sont
mockés. Ils vérifient les codes HTTP (201/400/409/422/503) et les métriques.

## Builder les images

```bash
eval "$(minikube docker-env)"                  # pour Minikube ; sinon docker build classique
docker build -t catalog-service:1.0.0 catalog-service
docker build -t order-service:1.0.0   order-service
```

Le `Dockerfile` est multi-stage : Maven + JDK pour compiler, `eclipse-temurin:21-jre-alpine` pour exécuter,
utilisateur `spring` non-root, `-XX:MaxRAMPercentage=75` pour respecter la limite mémoire du conteneur.

## Déployer avec les manifests bruts (`k8s/`)

| Fichier | Contenu |
|---------|---------|
| `00-namespace.yaml` | namespace `spring-demo` |
| `10-config.yaml` | ConfigMaps `catalog-config` (`CATALOG_ENVIRONMENT=kubernetes`) et `order-config` (`CATALOG_URL=http://catalog:8080`) |
| `20-catalog.yaml` | Deployment (2 réplicas, probes startup/liveness/readiness, resources) + Service `catalog` |
| `30-order.yaml` | idem pour `order` |
| `40-ingress.yaml` | Ingress `spring.local` : `/api/products` → catalog, `/api/orders` → order |

```bash
kubectl apply -f k8s/
kubectl -n spring-demo get pods
echo "$(minikube ip) spring.local" | sudo tee -a /etc/hosts
curl -s http://spring.local/api/products
```

La version Helm de ces manifests (paramétrable, multi-environnements) est dans
[`../106-helm/spring-demo`](../106-helm/spring-demo/).

## Modifier le code

1. Changez le Java, lancez `./mvnw verify`.
2. Rebuildez l'image avec un **nouveau tag** (`:1.1.0`) — jamais `:latest` en cluster.
3. `helm upgrade demo ../106-helm/spring-demo -n spring-helm --reuse-values --set order.image.tag=1.1.0 --wait`
4. `kubectl -n spring-helm rollout status deploy/demo-order` ; si problème : `helm rollback demo -n spring-helm`.
