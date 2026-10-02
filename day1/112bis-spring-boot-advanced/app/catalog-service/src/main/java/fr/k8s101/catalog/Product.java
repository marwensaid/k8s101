package fr.k8s101.catalog;

import java.math.BigDecimal;

public record Product(long id, String name, BigDecimal price, int stock) {
}
