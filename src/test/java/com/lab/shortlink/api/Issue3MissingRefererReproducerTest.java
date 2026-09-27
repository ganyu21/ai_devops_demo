package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lab.shortlink.visit.VisitLogService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * Issue #3 回归测试：不带 Referer 的跳转请求不应触发 500，
 * 应正常 302 跳转到目标地址，并将 referer 为 null 的访问记录落库。
 */
@SpringBootTest
@AutoConfigureMockMvc
class Issue3MissingRefererReproducerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
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
    void redirectWithoutRefererShouldNotReturn500() throws Exception {
        String targetUrl = "https://example.com/no-referer-target";
        String code = createLink(targetUrl);

        mockMvc.perform(get("/" + code))
                .andExpect(status().isFound())
                .andExpect(header().string(HttpHeaders.LOCATION, targetUrl));

        // 统计写入是异步旁路（OQ7 严格口径），落库可见性晚于响应返回，这里在测试线程做有界等待。
        VisitLogAwait.untilRecorded(visitLog, code, 1);

        assertThat(visitLog.snapshot())
                .filteredOn(record -> record.code().equals(code))
                .singleElement()
                .satisfies(record -> assertThat(record.referer()).isNull());
    }
}
