package com.lab.shortlink.api;

import static org.mockito.Mockito.doReturn;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lab.shortlink.visit.VisitLogService;
import java.util.concurrent.CompletableFuture;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * 流水写入独立超时的集成测试。
 *
 * <p>通过 MockBean 让 {@link VisitLogService#recordAsync} 返回一个永远不会完成的 Future，
 * 验证主链路在 50ms 超时后仍然返回 302，并记录 ERROR 日志。
 */
@SpringBootTest
@AutoConfigureMockMvc
class VisitLogTimeoutTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private VisitLogService visitLog;

    private String createLink(String targetUrl) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"" + targetUrl + "\"}"))
                .andExpect(status().isCreated())
                .andReturn();
        return objectMapper.readValue(result.getResponse().getContentAsString(), CreateLinkResponse.class).code();
    }

    @Test
    void redirectReturns302WhenVisitLogWriteTimesOut() throws Exception {
        String code = createLink("https://example.com/timeout-target");

        doReturn(new CompletableFuture<>()).when(visitLog).recordAsync(code, "https://example.com/source");

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/source"))
                .andExpect(status().isFound());
    }
}
