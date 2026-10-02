package fr.k8s101.order;

import java.math.BigDecimal;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

/**
 * Client HTTP vers catalog-service.
 * L'URL vient de la propriété {@code catalog.url}, donc de la variable d'env CATALOG_URL dans Kubernetes :
 * en local {@code http://localhost:8080}, dans le cluster {@code http://catalog:8080} (DNS du Service).
 */
@Component
public class CatalogClient {

    public record Product(long id, String name, BigDecimal price, int stock) {
    }

    private final RestClient restClient;

    public CatalogClient(RestClient.Builder builder, @Value("${catalog.url}") String catalogUrl) {
        this.restClient = builder.baseUrl(catalogUrl).build();
    }

    public Optional<Product> findProduct(long id) {
        try {
            return Optional.ofNullable(restClient.get()
                    .uri("/api/products/{id}", id)
                    .retrieve()
                    .body(Product.class));
        } catch (HttpClientErrorException e) {
            if (e.getStatusCode() == HttpStatus.NOT_FOUND) {
                return Optional.empty();
            }
            throw e;
        }
    }

    /** Appelle le endpoint liveness du catalogue ; lève une exception si injoignable. */
    public void ping() {
        restClient.get().uri("/actuator/health/liveness").retrieve().toBodilessEntity();
    }
}
