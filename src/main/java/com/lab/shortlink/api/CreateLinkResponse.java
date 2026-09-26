package com.lab.shortlink.api;

public record CreateLinkResponse(String code, String targetUrl, String shortUrl) {
}
