package com.lab.shortlink.visit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatNoException;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.lab.shortlink.visit.VisitLogService.VisitRecord;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

/**
 * 访问流水的单元测试。
 *
 * <p>这里<b>故意没有</b>「referer 为 null」的用例。缺失 Referer 属于正常流量
 * （见 {@code openapi.yaml} 里对那个请求头的说明），而那条路径归另一张工单负责：
 * 在这里补用例会把不属于本类的断言提前锁死，也会让那张工单失去
 * 「修复前红、修复后绿」的对比证据。
 *
 * <p>本类不描述那条路径当前的行为——描述了就等于替分诊环节把答案写出来。
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Transactional
class VisitLogServiceTest {

    @Autowired
    private VisitLogService visitLog;

    @Test
    void recordNormalizesTheRefererToLowerCase() {
        visitLog.record("Aa11Bb22", "HTTPS://Example.COM/Landing");

        assertThat(visitLog.findRecentByCode("Aa11Bb22", 10))
                .singleElement()
                .extracting(VisitRecord::referer)
                .isEqualTo("https://example.com/landing");
    }

    @Test
    void findRecentByCodeReturnsRecordsInReverseChronologicalOrder() throws InterruptedException {
        visitLog.record("Aa11Bb22", "https://example.com/first");
        TimeUnit.MILLISECONDS.sleep(10);
        visitLog.record("Aa11Bb22", "https://example.com/second");

        assertThat(visitLog.findRecentByCode("Aa11Bb22", 10))
                .extracting(VisitRecord::referer)
                .containsExactly("https://example.com/second", "https://example.com/first");
    }

    @Test
    void findRecentByCodeReturnsAnUnmodifiableList() {
        visitLog.record("Aa11Bb22", "https://example.com/first");

        assertThatThrownBy(() -> visitLog.findRecentByCode("Aa11Bb22", 10).add(
                new VisitRecord("Forged", "https://example.com/forged", java.time.Instant.now())))
                .isInstanceOf(UnsupportedOperationException.class);
        assertThat(visitLog.size()).isEqualTo(1);
    }

    @Test
    void sizeTracksEveryRecordedVisit() {
        visitLog.record("Aa11Bb22", "https://example.com/a");
        visitLog.record("Aa11Bb22", "https://example.com/b");
        visitLog.record("Cc33Dd44", "https://example.com/c");

        assertThat(visitLog.size()).isEqualTo(3);
    }

    @Test
    void findRecentByCodeLimitsTheResultSet() {
        visitLog.record("Aa11Bb22", "https://example.com/1");
        visitLog.record("Aa11Bb22", "https://example.com/2");
        visitLog.record("Aa11Bb22", "https://example.com/3");

        assertThat(visitLog.findRecentByCode("Aa11Bb22", 2)).hasSize(2);
    }

    /**
     * 线程池已关闭（应用停止中）时提交写入属于防御路径：只记 ERROR，不得向调用方抛异常，
     * 更不能让跳转主链路因此变成 5xx。用独立实例，避免关掉 Spring 上下文里共享的线程池。
     */
    @Test
    void submittingAfterTheExecutorIsShutDownOnlyLogsAndDoesNotThrow() {
        VisitLogService detached = new VisitLogService(mock(JdbcTemplate.class));
        detached.shutdown();

        assertThatNoException().isThrownBy(() -> detached.recordAsync("Aa11Bb22", "https://example.com/late"));
    }
}
