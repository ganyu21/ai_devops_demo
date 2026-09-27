package com.lab.shortlink.config;

import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "shortlink")
public class ShortlinkProperties {

    private String publicBaseUrl = "http://localhost:8081";

    private long redirectBudgetMillis = 300L;

    private Resolve resolve = new Resolve();

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

    @SuppressFBWarnings(
            value = { "EI_EXPOSE_REP" },
            justification = "Spring Boot configuration properties binding pattern")
    public Resolve getResolve() {
        return resolve;
    }

    @SuppressFBWarnings(
            value = { "EI_EXPOSE_REP2" },
            justification = "Spring Boot configuration properties binding pattern")
    public void setResolve(Resolve resolve) {
        this.resolve = resolve;
    }

    public static class Resolve {

        private Cache cache = new Cache();

        @SuppressFBWarnings(
                value = { "EI_EXPOSE_REP" },
                justification = "Spring Boot configuration properties binding pattern")
        public Cache getCache() {
            return cache;
        }

        @SuppressFBWarnings(
                value = { "EI_EXPOSE_REP2" },
                justification = "Spring Boot configuration properties binding pattern")
        public void setCache(Cache cache) {
            this.cache = cache;
        }
    }

    public static class Cache {

        private int maxSize = 10_000;

        private long ttlMinutes = 10L;

        public int getMaxSize() {
            return maxSize;
        }

        public void setMaxSize(int maxSize) {
            this.maxSize = maxSize;
        }

        public long getTtlMinutes() {
            return ttlMinutes;
        }

        public void setTtlMinutes(long ttlMinutes) {
            this.ttlMinutes = ttlMinutes;
        }
    }
}
