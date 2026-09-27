package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.fail;

import com.lab.shortlink.visit.VisitLogService;
import java.time.Duration;

/**
 * 统计写入是旁路（OQ7 严格口径）：redirect 请求返回时写入可能尚未可见，
 * 因此「跳转后立刻读库」天然是竞态。测试要观察落库结果时，先在这里做有界等待。
 *
 * <p>等待发生在测试线程，不在生产请求线程 —— 生产代码路径里没有任何同步等待。
 */
final class VisitLogAwait {

    private static final Duration TIMEOUT = Duration.ofSeconds(5);

    private VisitLogAwait() {
    }

    static void untilRecorded(VisitLogService visitLog, String code, int expectedCount) throws InterruptedException {
        long deadline = System.nanoTime() + TIMEOUT.toNanos();
        while (System.nanoTime() < deadline) {
            if (visitLog.findRecentByCode(code, 200).size() >= expectedCount) {
                return;
            }
            Thread.sleep(20);
        }
        fail("expected at least %d visit record(s) for code=%s within %s, but found %d",
                expectedCount, code, TIMEOUT, visitLog.findRecentByCode(code, 200).size());
    }
}
