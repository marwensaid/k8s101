package fr.k8s101.catalog;

import java.math.BigDecimal;
import java.net.InetAddress;
import java.net.UnknownHostException;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/products")
public class ProductController {

    private static final List<Product> PRODUCTS = List.of(
            new Product(1, "Casquette Kubernetes", new BigDecimal("19.90"), 42),
            new Product(2, "Mug Helm", new BigDecimal("12.50"), 7),
            new Product(3, "Sticker kubectl", new BigDecimal("1.00"), 1000),
            new Product(4, "T-shirt YAML", new BigDecimal("24.00"), 0));

    private final String environment;

    public ProductController(@Value("${catalog.environment:local}") String environment) {
        this.environment = environment;
    }

    @GetMapping
    public List<Product> all() {
        return PRODUCTS;
    }

    @GetMapping("/{id}")
    public Product byId(@PathVariable long id) {
        return PRODUCTS.stream()
                .filter(p -> p.id() == id)
                .findFirst()
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Produit " + id + " introuvable"));
    }

    // Utile pour voir quel Pod a répondu lorsqu'on scale le Deployment
    @GetMapping("/whoami")
    public Map<String, String> whoami() {
        return Map.of("hostname", hostname(), "environment", environment);
    }

    private static String hostname() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
