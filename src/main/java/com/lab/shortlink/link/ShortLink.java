package com.lab.shortlink.link;

import java.time.Instant;

public record ShortLink(String code, String targetUrl, Instant createdAt) {
}
