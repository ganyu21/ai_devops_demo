package com.lab.shortlink.visit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lab.shortlink.visit.VisitLogService.VisitRecord;
import org.junit.jupiter.api.Test;

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
class VisitLogServiceTest {

    private final VisitLogService visitLog = new VisitLogService();

    @Test
    void recordNormalizesTheRefererToLowerCase() {
        visitLog.record("Aa11Bb22", "HTTPS://Example.COM/Landing");

        assertThat(visitLog.snapshot())
                .singleElement()
                .extracting(VisitRecord::referer)
                .isEqualTo("https://example.com/landing");
    }

    @Test
    void snapshotPreservesInsertionOrder() {
        visitLog.record("Aa11Bb22", "https://example.com/first");
        visitLog.record("Cc33Dd44", "https://example.com/second");

        assertThat(visitLog.snapshot())
                .extracting(VisitRecord::code)
                .containsExactly("Aa11Bb22", "Cc33Dd44");
    }

    @Test
    void snapshotCannotBeUsedToMutateTheLog() {
        visitLog.record("Aa11Bb22", "https://example.com/first");

        assertThatThrownBy(() -> visitLog.snapshot().add(
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
}
