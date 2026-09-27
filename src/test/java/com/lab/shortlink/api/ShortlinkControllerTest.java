package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lab.shortlink.visit.VisitLogService;
import com.lab.shortlink.visit.VisitLogService.VisitRecord;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

/**
 * 对外契约的集成测试。
 *
 * <p>每一个跳转用例都<b>显式带上 Referer</b>。不带 Referer 的那条路径归另一张工单负责，
 * 本类不覆盖它——覆盖了就会把那张工单「修复前红、修复后绿」的对比证据提前消耗掉。
 */
@SpringBootTest
@AutoConfigureMockMvc
class ShortlinkControllerTest {

    private static final String REFERER = "https://example.com/landing-page";

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
    void createReturns201WithCodeLocationAndBody() throws Exception {
        MvcResult result = mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"https://example.com/a/very/long/path\"}"))
                .andExpect(status().isCreated())
                .andExpect(header().string(HttpHeaders.LOCATION, org.hamcrest.Matchers.containsString("/")))
                .andReturn();

        CreateLinkResponse body =
                objectMapper.readValue(result.getResponse().getContentAsString(), CreateLinkResponse.class);
        assertThat(body.code()).hasSize(8);
        assertThat(body.targetUrl()).isEqualTo("https://example.com/a/very/long/path");
        assertThat(body.shortUrl()).endsWith("/" + body.code());
        assertThat(result.getResponse().getHeader(HttpHeaders.LOCATION)).isEqualTo(body.shortUrl());
    }

    @Test
    void createRejectsABlankTargetUrl() throws Exception {
        mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void createRejectsAMalformedTargetUrl() throws Exception {
        mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"not a url at all\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void redirectReturns302PointingAtTheTargetUrl() throws Exception {
        String code = createLink("https://example.com/redirect-target");

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, REFERER))
                .andExpect(status().isFound())
                .andExpect(header().string(HttpHeaders.LOCATION, "https://example.com/redirect-target"));
    }

    @Test
    void redirectReturns404ForAnUnknownCode() throws Exception {
        mockMvc.perform(get("/unknown1").header(HttpHeaders.REFERER, REFERER))
                .andExpect(status().isNotFound());
    }

    @Test
    void redirectRecordsTheVisitWithANormalizedReferer() throws Exception {
        String code = createLink("https://example.com/visit-target");

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "HTTPS://Example.COM/Search?Q=1"))
                .andExpect(status().isFound());

        assertThat(visitLog.findRecentByCode(code, 10))
                .singleElement()
                .extracting(VisitRecord::referer)
                .isEqualTo("https://example.com/search?q=1");
    }

    @Test
    void aLinkCreatedThroughTheApiIsResolvableImmediately() throws Exception {
        MvcResult created = mockMvc.perform(post("/api/links")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUrl\":\"https://example.com/end-to-end\"}"))
                .andExpect(status().isCreated())
                .andReturn();
        CreateLinkResponse body =
                objectMapper.readValue(created.getResponse().getContentAsString(), CreateLinkResponse.class);

        mockMvc.perform(get("/" + body.code()).header(HttpHeaders.REFERER, REFERER))
                .andExpect(status().isFound())
                .andExpect(header().string(HttpHeaders.LOCATION, "https://example.com/end-to-end"));
    }

    @Test
    void visitsEndpointReturnsRecentVisitsInReverseChronologicalOrder() throws Exception {
        String code = createLink("https://example.com/visits-target");

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/source-a"))
                .andExpect(status().isFound());
        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/source-b"))
                .andExpect(status().isFound());

        MvcResult result = mockMvc.perform(get("/api/links/" + code + "/visits"))
                .andExpect(status().isOk())
                .andReturn();
        List<VisitRecord> visits = objectMapper.readValue(
                result.getResponse().getContentAsString(),
                objectMapper.getTypeFactory().constructCollectionType(List.class, VisitRecord.class));

        assertThat(visits).hasSize(2);
        assertThat(visits).extracting(VisitRecord::referer)
                .containsExactly("https://example.com/source-b", "https://example.com/source-a");
    }

    @Test
    void visitsEndpointRespectsTheLimitParameter() throws Exception {
        String code = createLink("https://example.com/visits-limit-target");

        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/1"))
                .andExpect(status().isFound());
        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/2"))
                .andExpect(status().isFound());
        mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/3"))
                .andExpect(status().isFound());

        MvcResult result = mockMvc.perform(get("/api/links/" + code + "/visits?limit=2"))
                .andExpect(status().isOk())
                .andReturn();
        List<VisitRecord> visits = objectMapper.readValue(
                result.getResponse().getContentAsString(),
                objectMapper.getTypeFactory().constructCollectionType(List.class, VisitRecord.class));

        assertThat(visits).hasSize(2);
    }

    @Test
    void visitsEndpointCapsLimitAtTheHardMaximum() throws Exception {
        String code = createLink("https://example.com/visits-max-target");

        for (int i = 0; i < 5; i++) {
            mockMvc.perform(get("/" + code).header(HttpHeaders.REFERER, "https://example.com/" + i))
                    .andExpect(status().isFound());
        }

        MvcResult result = mockMvc.perform(get("/api/links/" + code + "/visits?limit=999"))
                .andExpect(status().isOk())
                .andReturn();
        List<VisitRecord> visits = objectMapper.readValue(
                result.getResponse().getContentAsString(),
                objectMapper.getTypeFactory().constructCollectionType(List.class, VisitRecord.class));

        assertThat(visits).hasSize(5);
    }
}
