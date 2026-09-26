package com.lab.shortlink.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "shortlink")
public class ShortlinkProperties {

    private String publicBaseUrl = "http://localhost:8081";

    private long redirectBudgetMillis = 300L;

    public String getPublicBaseUrl() {
        return publicBaseUrl;
    }

    public void setPublicBaseUrl(String publicBaseUrl) {
        this.publicBaseUrl = publicBaseUrl;
    }

    public long getRedirectBudgetMillis() {
        return redirectBudgetMillis;
    }

    public void setRedirectBudgetMillis(long redirectBudgetMillis) {
        this.redirectBudgetMillis = redirectBudgetMillis;
    }
}
