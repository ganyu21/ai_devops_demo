package com.lab.shortlink.api;

import com.lab.shortlink.code.ShortCodeGenerator;
import com.lab.shortlink.config.ShortlinkProperties;
import com.lab.shortlink.link.LinkStore;
import com.lab.shortlink.link.ShortLink;
import com.lab.shortlink.resolve.LinkResolver;
import com.lab.shortlink.visit.VisitLogService;
import com.lab.shortlink.visit.VisitLogService.VisitRecord;
import jakarta.validation.Valid;
import java.net.URI;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ShortlinkController {

    private static final Logger LOG = LoggerFactory.getLogger(ShortlinkController.class);

    private static final int VISITS_DEFAULT_LIMIT = 50;

    private static final int VISITS_MAX_LIMIT = 200;

    private final ShortCodeGenerator codeGenerator;

    private final LinkStore store;

    private final LinkResolver resolver;

    private final VisitLogService visitLog;

    private final String publicBaseUrl;

    private final long redirectBudgetMillis;

    public ShortlinkController(ShortCodeGenerator codeGenerator, LinkStore store, LinkResolver resolver,
            VisitLogService visitLog, ShortlinkProperties properties) {
        this.codeGenerator = codeGenerator;
        this.store = store;
        this.resolver = resolver;
        this.visitLog = visitLog;
        this.publicBaseUrl = properties.getPublicBaseUrl();
        this.redirectBudgetMillis = properties.getRedirectBudgetMillis();
    }

    @PostMapping("/api/links")
    public ResponseEntity<CreateLinkResponse> create(@Valid @RequestBody CreateLinkRequest request) {
        String code = codeGenerator.next();
        while (store.findByCode(code).isPresent()) {
            code = codeGenerator.next();
        }
        ShortLink saved = new ShortLink(code, request.targetUrl(), Instant.now());
        store.save(saved);
        resolver.invalidate(code);
        String shortUrl = publicBaseUrl + "/" + code;
        LOG.info("link created code={} target={}", code, saved.targetUrl());
        return ResponseEntity.created(URI.create(shortUrl))
                .body(new CreateLinkResponse(code, saved.targetUrl(), shortUrl));
    }

    @GetMapping("/{code}")
    public ResponseEntity<Void> redirect(@PathVariable("code") String code,
            @RequestHeader(value = HttpHeaders.REFERER, required = false) String referer) {
        long startedAt = System.nanoTime();
        Optional<ShortLink> link = resolver.resolve(code);
        if (link.isEmpty()) {
            return ResponseEntity.notFound().build();
        }
        visitLog.recordAsync(code, referer);
        long elapsedMillis = TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt);
        if (elapsedMillis > redirectBudgetMillis) {
            LOG.warn("redirect budget exceeded code={} elapsedMs={} budgetMs={}",
                    code, elapsedMillis, redirectBudgetMillis);
        }
        return ResponseEntity.status(HttpStatus.FOUND).location(URI.create(link.get().targetUrl())).build();
    }

    @GetMapping("/api/links/{code}/visits")
    public ResponseEntity<List<VisitRecord>> visits(@PathVariable("code") String code,
            @RequestParam(name = "limit", required = false) Integer limit) {
        int effectiveLimit = effectiveLimit(limit);
        return ResponseEntity.ok(visitLog.findRecentByCode(code, effectiveLimit));
    }

    private int effectiveLimit(Integer limit) {
        if (limit == null || limit <= 0) {
            return VISITS_DEFAULT_LIMIT;
        }
        return Math.min(limit, VISITS_MAX_LIMIT);
    }
}
