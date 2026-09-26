package com.lab.shortlink.api;

import jakarta.validation.constraints.NotBlank;
import org.hibernate.validator.constraints.URL;

public record CreateLinkRequest(@NotBlank @URL String targetUrl) {
}
