package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.InputStream;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

/**
 * 冻结契约的机械检查。
 *
 * <p>{@code resources/api/openapi.yaml} 里已经发布的两个路径，自需求基线冻结后对下游只读。
 * 这里断言的是「既有定义还在、形状没变」，<b>不是</b>「不许新增路径」——
 * 新增统计查询接口是本次需求的一部分，属于允许的纯新增。
 */
class OpenApiContractTest {

    @SuppressWarnings("unchecked")
    private static Map<String, Object> spec() throws IOException {
        try (InputStream in = OpenApiContractTest.class.getResourceAsStream("/api/openapi.yaml")) {
            assertThat(in).as("classpath resource api/openapi.yaml must exist").isNotNull();
            return new Yaml().loadAs(in, Map.class);
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> paths() throws IOException {
        return (Map<String, Object>) spec().get("paths");
    }

    @Test
    void theTwoPublishedPathsKeepTheirExistingOperationsAndResponseCodes() throws IOException {
        Map<String, Object> paths = paths();

        assertThat(paths).containsKeys("/api/links", "/{code}");

        Map<String, Object> create = (Map<String, Object>) paths.get("/api/links");
        assertThat(create).containsKey("post");
        Map<String, Object> createResponses = (Map<String, Object>) create.get("post");
        assertThat((Map<String, Object>) createResponses.get("responses")).containsKeys("201", "400");
        Map<String, Object> requestBody = (Map<String, Object>) createResponses.get("requestBody");
        assertThat(requestBody.get("required")).isEqualTo(true);

        Map<String, Object> redirect = (Map<String, Object>) paths.get("/{code}");
        assertThat(redirect).containsKey("get");
        Map<String, Object> redirectOp = (Map<String, Object>) redirect.get("get");
        assertThat((Map<String, Object>) redirectOp.get("responses")).containsKeys("302", "404");
    }

    @Test
    void refererStaysOptionalAndDocumentedAsNormalTraffic() throws IOException {
        Map<String, Object> redirectOp =
                (Map<String, Object>) ((Map<String, Object>) paths().get("/{code}")).get("get");
        List<Map<String, Object>> parameters = (List<Map<String, Object>>) redirectOp.get("parameters");

        Map<String, Object> referer = parameters.stream()
                .filter(parameter -> "Referer".equals(parameter.get("name")))
                .findFirst()
                .orElseThrow(() -> new AssertionError("the Referer header parameter disappeared from the contract"));

        assertThat(referer.get("in")).isEqualTo("header");
        assertThat(referer.get("required")).isEqualTo(false);
        assertThat(String.valueOf(referer.get("description")))
                .as("the contract must keep saying that a missing Referer is normal traffic, not an attack")
                .contains("正常流量");
    }

    @Test
    void createLinkRequestKeepsTargetUrlRequired() throws IOException {
        Map<String, Object> components = (Map<String, Object>) spec().get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> request = (Map<String, Object>) schemas.get("CreateLinkRequest");

        assertThat((List<String>) request.get("required")).containsExactly("targetUrl");
        assertThat((Map<String, Object>) request.get("properties")).containsKey("targetUrl");
    }
}
