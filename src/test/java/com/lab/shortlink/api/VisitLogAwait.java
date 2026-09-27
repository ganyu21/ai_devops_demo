package com.lab.shortlink.api;

import static org.assertj.core.api.Assertions.fail;

import com.lab.shortlink.visit.VisitLogService;
import java.time.Duration;

/**
 * 统计写入是旁路（OQ7 严格口径）：redirect 请求返回时写入可能尚未可见，
 * 因此「跳转后立刻读库」天然是竞态。测试要观察落库结果时，先在这里做有界等待。
 *
 * <p>等待发生在测试线程，不在生产请求线程 —— 生产代码路径里没有任何同步等待。
 *
 * <p>观测窗口故意给得宽：正常路径毫秒级返回（轮询到即返回），窗口只是给高负载 CI 留余量。
 * 放宽窗口<b>不放宽断言</b>——真丢写时用例会在窗口耗尽后失败并打印最后观测值，不会静默通过。
 */
final class VisitLogAwait {

    private static final Duration TIMEOUT = Duration.ofSeconds(15);

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
        int lastObserved = visitLog.findRecentByCode(code, 200).size();
        String message = "expected at least %d visit record(s) for code=%s within the %s"
                + " observation window, but the last observed count was %d"
                + " (statistics are an asynchronous bypass, so this failure means the observation"
                + " window was exceeded on a slow/loaded runner, not that the redirect path blocked)";
        fail(message, expectedCount, code, TIMEOUT, lastObserved);
    }
}
