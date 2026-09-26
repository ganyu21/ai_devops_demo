package com.lab.shortlink.visit;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.lab.shortlink.visit.VisitLogService.VisitRecord;
import org.junit.jupiter.api.Test;

/**
 * 访问流水的单元测试。
 *
 * <p>这里<b>故意没有</b>「referer 为 null」的用例。缺失 Referer 是正常流量，
 * 而当前实现在这种情况下会抛 NullPointerException —— 那是另一张工单要修的线上缺陷。
 * 如果在这里补一个 null 用例，基线就会是红的，而那个红本该属于热修工单，
 * 它的「修复前红、修复后绿」对比证据也就没了。
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
