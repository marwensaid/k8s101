package fr.k8s101.order;

import java.math.BigDecimal;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.List;
import java.util.Map;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/orders")
public class OrderController {

    public record OrderRequest(long productId, int quantity) {
    }

    private final CatalogClient catalogClient;
    private final OrderRepository repository;
    // Métrique métier exposée sur /actuator/prometheus (module 109) : orders_placed_total{outcome="success|rejected"}
    // NB : évitez les noms finissant par _created, _total ou _count : suffixes réservés OpenMetrics, ils seraient supprimés.
    private final Counter created;
    private final Counter rejected;

    public OrderController(CatalogClient catalogClient, OrderRepository repository, MeterRegistry registry) {
        this.catalogClient = catalogClient;
        this.repository = repository;
        this.created = Counter.builder("orders.placed").tag("outcome", "success").register(registry);
        this.rejected = Counter.builder("orders.placed").tag("outcome", "rejected").register(registry);
    }

    @GetMapping
    public List<Order> all() {
        return repository.findAll();
    }

    @GetMapping("/{id}")
    public Order byId(@PathVariable long id) {
        return repository.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Commande " + id + " introuvable"));
    }

    @GetMapping("/whoami")
    public Map<String, Object> whoami() {
        return Map.of("hostname", hostname(), "orders", repository.count());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Order create(@RequestBody OrderRequest request) {
        if (request.quantity() <= 0) {
            rejected.increment();
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "quantity doit être > 0");
        }

        CatalogClient.Product product;
        try {
            product = catalogClient.findProduct(request.productId())
                    .orElseThrow(() -> {
                        rejected.increment();
                        return new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY,
                                "Produit " + request.productId() + " inconnu du catalogue");
                    });
        } catch (ResourceAccessException e) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Catalogue injoignable : " + e.getMessage());
        }

        if (product.stock() < request.quantity()) {
            rejected.increment();
            throw new ResponseStatusException(HttpStatus.CONFLICT,
                    "Stock insuffisant pour " + product.name() + " (" + product.stock() + " disponible(s))");
        }

        BigDecimal total = product.price().multiply(BigDecimal.valueOf(request.quantity()));
        Order order = repository.save(new Order(product.id(), product.name(), request.quantity(), total));
        created.increment();
        return order;
    }

    private static String hostname() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
