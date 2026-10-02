package fr.k8s101.order;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.math.BigDecimal;
import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.boot.actuate.autoconfigure.metrics.CompositeMeterRegistryAutoConfiguration;
import org.springframework.boot.actuate.autoconfigure.metrics.MetricsAutoConfiguration;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(OrderController.class)
@Import({MetricsAutoConfiguration.class, CompositeMeterRegistryAutoConfiguration.class})
class OrderControllerTest {

    @Autowired
    MockMvc mvc;

    @MockitoBean
    CatalogClient catalogClient;

    @MockitoBean
    OrderRepository repository;

    @Test
    void createsOrderWhenProductExistsAndStockIsEnough() throws Exception {
        when(catalogClient.findProduct(2L))
                .thenReturn(Optional.of(new CatalogClient.Product(2, "Mug Helm", new BigDecimal("12.50"), 7)));
        when(repository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));

        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"productId\":2,\"quantity\":3}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.productName").value("Mug Helm"))
                .andExpect(jsonPath("$.total").value(37.50));
    }

    @Test
    void rejectsUnknownProduct() throws Exception {
        when(catalogClient.findProduct(anyLong())).thenReturn(Optional.empty());

        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"productId\":99,\"quantity\":1}"))
                .andExpect(status().isUnprocessableEntity());
    }

    @Test
    void rejectsInsufficientStock() throws Exception {
        when(catalogClient.findProduct(4L))
                .thenReturn(Optional.of(new CatalogClient.Product(4, "T-shirt YAML", new BigDecimal("24.00"), 0)));

        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"productId\":4,\"quantity\":1}"))
                .andExpect(status().isConflict());
    }
}
