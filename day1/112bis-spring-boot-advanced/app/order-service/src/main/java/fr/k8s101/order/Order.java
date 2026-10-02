package fr.k8s101.order;

import java.math.BigDecimal;
import java.time.Instant;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

/**
 * Commande persistée via JPA.
 * Par défaut la base est H2 en mémoire (chaque Pod a la sienne) ; au module 112 on la remplace par PostgreSQL
 * simplement en surchargeant SPRING_DATASOURCE_URL.
 */
@Entity
@Table(name = "orders")
public class Order {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private long productId;
    private String productName;
    private int quantity;
    private BigDecimal total;
    private Instant createdAt;

    protected Order() {
        // requis par JPA
    }

    public Order(long productId, String productName, int quantity, BigDecimal total) {
        this.productId = productId;
        this.productName = productName;
        this.quantity = quantity;
        this.total = total;
        this.createdAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public long getProductId() {
        return productId;
    }

    public String getProductName() {
        return productName;
    }

    public int getQuantity() {
        return quantity;
    }

    public BigDecimal getTotal() {
        return total;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
