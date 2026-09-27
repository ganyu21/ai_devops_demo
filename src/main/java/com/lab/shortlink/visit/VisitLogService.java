package com.lab.shortlink.visit;

import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;
import jakarta.annotation.PreDestroy;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

/**
 * 访问流水。
 *
 * <p>把访问流水持久化到 H2 数据库，并提供按短码查询最近访问的能力。
 * 缺失 Referer 时保存 {@code null}，否则按 {@link Locale#ROOT} 归一化为小写。
 */
@Service
public class VisitLogService {

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
     * <p>当 referer 缺失时保存 {@code null}；存在时按 {@link Locale#ROOT} 转小写后落库。
     */
    public void record(String code, String referer) {
        String normalized = referer == null ? null : referer.toLowerCase(Locale.ROOT);
        jdbc.update("INSERT INTO visit_log (code, referer, visited_at) VALUES (?, ?, ?)",
                code, normalized, Timestamp.from(Instant.now()));
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

    /**
     * 返回全部访问流水的快照，按 visited_at 倒序排列。
     */
    public List<VisitRecord> snapshot() {
        return List.copyOf(jdbc.query(
                "SELECT code, referer, visited_at FROM visit_log ORDER BY visited_at DESC",
                (rs, rowNum) -> new VisitRecord(
                        rs.getString("code"),
                        rs.getString("referer"),
                        rs.getTimestamp("visited_at").toInstant())));
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
