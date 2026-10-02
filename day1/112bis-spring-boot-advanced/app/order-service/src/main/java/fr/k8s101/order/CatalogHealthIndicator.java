package fr.k8s101.order;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Remonte l'état du catalogue dans /actuator/health/catalog.
 * Il est inclus dans le groupe "readiness" (voir application.yaml) : si le catalogue est injoignable,
 * order-service devient NotReady et Kubernetes le retire du Service, sans le redémarrer.
 */
@Component("catalog")
public class CatalogHealthIndicator implements HealthIndicator {

    private final CatalogClient catalogClient;

    public CatalogHealthIndicator(CatalogClient catalogClient) {
        this.catalogClient = catalogClient;
    }

    @Override
    public Health health() {
        try {
            catalogClient.ping();
            return Health.up().build();
        } catch (Exception e) {
            return Health.down().withDetail("error", e.getMessage()).build();
        }
    }
}
