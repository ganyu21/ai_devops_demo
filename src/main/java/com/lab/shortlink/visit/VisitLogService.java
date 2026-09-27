package com.lab.shortlink.visit;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Service;

/**
 * 访问流水。
 *
 * <p>当前实现把流水放在进程内存的一个 {@link List} 里：进程重启即丢，
 * 多实例之间互不可见，因此支撑不了任何按引流来源统计的查询。
 */
@Service
public class VisitLogService {

    private final List<VisitRecord> records = Collections.synchronizedList(new ArrayList<>());

    public void record(String code, String referer) {
        String normalized = referer == null ? null : referer.toLowerCase(Locale.ROOT);
        records.add(new VisitRecord(code, normalized, Instant.now()));
    }

    public List<VisitRecord> snapshot() {
        synchronized (records) {
            return List.copyOf(records);
        }
    }

    public int size() {
        return records.size();
    }

    public record VisitRecord(String code, String referer, Instant visitedAt) {
    }
}
