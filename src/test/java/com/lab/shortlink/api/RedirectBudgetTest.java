package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lab.shortlink.config.ShortlinkProperties;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * 跳转预算是对外承诺：{@code shortlink.redirect-budget-millis} 默认 300ms。
 *
 * <p>这条承诺最容易被「顺手加一点东西」打破 —— 比如在跳转主链路上同步写一次数据库、
 * 或者加一次远程调用。所以它由一个测试守着，而不是靠人记得。
 */
@SpringBootTest
@AutoConfigureMockMvc
class RedirectBudgetTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private ShortlinkProperties properties;

    @Test
    void redirectCompletesWithinThePublishedBudget() throws Exception {
        MvcResult created = mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"https://example.com/budget-target\"}"))
                .andExpect(status().isCreated())
                .andReturn();
        String code = objectMapper.readValue(created.getResponse().getContentAsString(), CreateLinkResponse.class)
                .code();

        // 预热一次：首跳要付上下文与 JIT 的一次性成本，量的应当是稳定态而不是冷启动。
        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/warmup"))
                .andExpect(status().isFound());

        long startedAt = System.nanoTime();
        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/measured"))
                .andExpect(status().isFound());
        long elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);

        assertThat(elapsedMillis)
                .as("redirect must stay inside the published budget of %d ms",
                        properties.getRedirectBudgetMillis())
                .isLessThan(properties.getRedirectBudgetMillis());
    }
}
