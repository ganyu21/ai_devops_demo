package com.lab.shortlink.resolve;

import com.lab.shortlink.link.LinkStore;
import com.lab.shortlink.link.ShortLink;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.springframework.stereotype.Component;

/**
 * 带解析缓存的链接解析器。
 *
 * <p>当前实现有两个<b>已知缺陷</b>，它们是需求单要解决的对象，在需求实现之前必须保持现状：
 *
 * <ol>
 *   <li>缓存没有容量上限，条目也不会过期。每一个被访问过的短码都会在堆里留一条记录，
 *       长期运行就是慢性内存泄漏。
 *   <li>目标地址被更正之后，缓存里的旧条目仍然生效，访问者会一直被跳到旧地址，
 *       直到进程重启。
 * </ol>
 */
@Component
public class CachingLinkResolver implements LinkResolver {

    private final ConcurrentMap<String, Optional<ShortLink>> cache = new ConcurrentHashMap<>();

    private final LinkStore store;

    public CachingLinkResolver(LinkStore store) {
        this.store = store;
    }

    @Override
    public Optional<ShortLink> resolve(String code) {
        return cache.computeIfAbsent(code, store::findByCode);
    }

    @Override
    public int cachedEntries() {
        return cache.size();
    }
}
