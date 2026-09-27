package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.fail;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Duration;
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
 * 旁路写入的任何失败都不许放大成主链路 5xx。
 *
 * <p>历史实现里 {@code NullPointerException} 被原样重抛（为保留 #3 的 500 行为）。
 * #3 的空值保护合并后该分支已不可达；本次返修直接删除该分支：
 * 无论旁路因何失败（含 NPE），都只记 ERROR，跳转保持 302。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ExtendWith(OutputCaptureExtension.class)
class VisitLogBypassFailureTest {

    private static final Duration LOG_WAIT = Duration.ofSeconds(5);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

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
    void failingVisitLogWriteMustNotTurnTheRedirectIntoA5xx(CapturedOutput output) throws Exception {
        String targetUrl = "https://example.com/bypass-failure-target";
        when(jdbc.update(anyString(), any(), any(), any()))
                .thenThrow(new NullPointerException("simulated visit-log write failure"));

        String code = createLink(targetUrl);

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/failing-source"))
                .andExpect(status().isFound())
                .andExpect(header().string(HttpHeaders.LOCATION, targetUrl));

        awaitLog(output, "visit log write failed");
    }
}
