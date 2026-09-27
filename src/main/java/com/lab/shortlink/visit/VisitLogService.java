package com.lab.shortlink.visit;

import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;
import jakarta.annotation.PreDestroy;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * 访问流水。
 *
 * <p>把访问流水持久化到 H2 数据库，并提供按短码查询最近访问的能力。
 */
@Service
public class VisitLogService {

    private static final Logger LOG = LoggerFactory.getLogger(VisitLogService.class);

    private final JdbcTemplate jdbc;

    private final ExecutorService executor;

    @SuppressFBWarnings(
            value = { "EI_EXPOSE_REP2" },
            justification = "JdbcTemplate is a Spring-managed immutable service")
    public VisitLogService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
        this.executor = Executors.newFixedThreadPool(2, new VisitLogThreadFactory());
    }

    /**
     * 同步记录一次访问。
     *
     * <p>对 referer 的处理与基线逐字一致：直接调用 {@code toLowerCase(Locale.ROOT)}，
     * 不添加空值保护。缺失 Referer 时的 500 缺陷由 issue #3 独立热修处理。
     */
    public void record(String code, String referer) {
        String normalized = referer.toLowerCase(Locale.ROOT);
        jdbc.update("INSERT INTO visit_log (code, referer, visited_at) VALUES (?, ?, ?)",
                code, normalized, java.sql.Timestamp.from(Instant.now()));
    }

    /**
     * 异步记录一次访问，返回 Future 以便调用方控制超时。
     */
    public Future<?> recordAsync(String code, String referer) {
        return executor.submit(() -> record(code, referer));
    }

    /**
     * 按短码查询最近访问流水，按 visited_at 倒序返回。
     */
    public List<VisitRecord> findRecentByCode(String code, int limit) {
        return List.copyOf(jdbc.query(
                "SELECT code, referer, visited_at FROM visit_log WHERE code = ? ORDER BY visited_at DESC LIMIT ?",
                (rs, rowNum) -> new VisitRecord(
                        rs.getString("code"),
                        rs.getString("referer"),
                        rs.getTimestamp("visited_at").toInstant()),
                code, limit));
    }

    public int size() {
        Integer count = jdbc.queryForObject("SELECT COUNT(*) FROM visit_log", Integer.class);
        return count == null ? 0 : count;
    }

    @PreDestroy
    public void shutdown() {
        executor.shutdownNow();
    }

    public record VisitRecord(String code, String referer, Instant visitedAt) {
    }

    private static final class VisitLogThreadFactory implements ThreadFactory {

        private final AtomicInteger counter = new AtomicInteger();

        @Override
        public Thread newThread(Runnable runnable) {
            Thread thread = new Thread(runnable, "visit-log-writer-" + counter.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        }
    }
}
