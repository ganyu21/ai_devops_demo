package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.fail;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lab.shortlink.config.ShortlinkProperties;
import java.time.Duration;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * 统计写入是旁路：DB 慢写不得进入跳转请求线程的等待路径，更不得挤占对外承诺的 300ms 跳转预算。
 *
 * <p>用 {@code @MockBean JdbcTemplate} 把落库卡住，验证三件事：
 * 302 与 Location 正常返回；请求耗时小于跳转预算；超预算后记 ERROR。
 * 同时验证「超预算」的语义只是<b>不再等待</b>——写入任务没有被取消，
 * 放开阻塞后仍然执行完成（DB 慢写时数据最终可能落库）。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class VisitLogTimeoutTest {

    private static final Duration LOG_WAIT = Duration.ofSeconds(5);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private ShortlinkProperties properties;

    @MockBean
    private JdbcTemplate jdbc;

    private String createLink(String targetUrl) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"" + targetUrl + "\"}"))
                .andExpect(status().isCreated())
                .andReturn();
        return objectMapper.readValue(result.getResponse().getContentAsString(), CreateLinkResponse.class).code();
    }

    private static void awaitLog(CapturedOutput output, String fragment) throws InterruptedException {
        long deadline = System.nanoTime() + LOG_WAIT.toNanos();
        while (System.nanoTime() < deadline) {
            if (output.getAll().contains(fragment)) {
                return;
            }
            Thread.sleep(20);
        }
        fail("expected log fragment not found within %s: %s", LOG_WAIT, fragment);
    }

    @Test
    void slowWriteNeverBlocksTheRedirectNorBreaksTheBudget(CapturedOutput output) throws Exception {
        String targetUrl = "https://example.com/slow-write-target";
        CountDownLatch writeStarted = new CountDownLatch(1);
        CountDownLatch releaseWrite = new CountDownLatch(1);
        CountDownLatch writeFinished = new CountDownLatch(1);
        when(jdbc.update(anyString(), any(), any(), any())).thenAnswer(invocation -> {
            writeStarted.countDown();
            releaseWrite.await();
            writeFinished.countDown();
            return 1;
        });

        try {
            String code = createLink(targetUrl);

            long startedAt = System.nanoTime();
            mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/slow-source"))
                    .andExpect(status().isFound())
                    .andExpect(header().string(HttpHeaders.LOCATION, targetUrl));
            long elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);

            assertThat(elapsedMillis)
                    .as("redirect must not wait for the visit-log write; budget is %d ms",
                            properties.getRedirectBudgetMillis())
                    .isLessThan(properties.getRedirectBudgetMillis());
            assertThat(writeStarted.await(1, TimeUnit.SECONDS))
                    .as("the bypass write should have been submitted to the background executor")
                    .isTrue();

            awaitLog(output, "visit log write exceeded");

            releaseWrite.countDown();
            assertThat(writeFinished.await(2, TimeUnit.SECONDS))
                    .as("exceeding the budget stops waiting but does not cancel the write")
                    .isTrue();
        } finally {
            releaseWrite.countDown();
        }
    }
}
