package com.lab.shortlink.visit;

import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;
import jakarta.annotation.PreDestroy;
import java.sql.Timestamp;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger LOG = LoggerFactory.getLogger(VisitLogService.class);

    /**
     * 旁路写入的独立预算。超过后只停止等待并记 ERROR，不中断底层写入。
     */
    static final long WRITE_BUDGET_MILLIS = 50;

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
     * 异步记录一次访问：提交后立即返回，调用线程（跳转请求线程）不被统计写入阻塞。
     *
     * <p>写入超过 {@value #WRITE_BUDGET_MILLIS}ms 预算或失败时只记 ERROR 日志，不影响调用方。
     * 注意「超预算」的语义是<b>不再等待</b>，不是取消写入：底层任务不会被中断，
     * DB 慢写时数据最终仍可能落库，也不做重试或补偿。
     */
    public void recordAsync(String code, String referer) {
        try {
            CompletableFuture.runAsync(() -> record(code, referer), executor)
                    .orTimeout(WRITE_BUDGET_MILLIS, TimeUnit.MILLISECONDS)
                    .whenComplete((ignored, failure) -> logBypassFailure(code, failure));
        } catch (RuntimeException e) {
            LOG.error("visit log write submission failed code={}", code, e);
        }
    }

    private static void logBypassFailure(String code, Throwable failure) {
        if (failure == null) {
            return;
        }
        Throwable cause = failure instanceof CompletionException && failure.getCause() != null
                ? failure.getCause()
                : failure;
        if (cause instanceof TimeoutException) {
            LOG.error("visit log write exceeded {}ms budget code={}", WRITE_BUDGET_MILLIS, code);
        } else {
            LOG.error("visit log write failed code={}", code, cause);
        }
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
