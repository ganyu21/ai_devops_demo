package com.lab.shortlink.resolve;

import com.lab.shortlink.config.ShortlinkProperties;
import com.lab.shortlink.link.LinkStore;
import com.lab.shortlink.link.ShortLink;
import java.time.Duration;
import java.time.Instant;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

/**
 * 带解析缓存的链接解析器。
 *
 * <p>缓存具备可配置的容量上限、TTL 与 LRU 淘汰策略；在保存/更正链接的写路径上
 * 主动失效对应短码的缓存条目，保证目标地址更新后能尽快生效。
 */
@Component
public class CachingLinkResolver implements LinkResolver {

    private final LinkStore store;

    private final Duration ttl;

    private final Object lock = new Object();

    private final LruCache cache;

    @Autowired
    public CachingLinkResolver(LinkStore store, ShortlinkProperties properties) {
        this(store, properties.getResolve().getCache().getMaxSize(),
                Duration.ofMinutes(properties.getResolve().getCache().getTtlMinutes()));
    }

    CachingLinkResolver(LinkStore store, int maxSize, Duration ttl) {
        this.store = store;
        this.ttl = ttl;
        this.cache = new LruCache(maxSize);
    }

    @Override
    public Optional<ShortLink> resolve(String code) {
        synchronized (lock) {
            CacheEntry entry = cache.get(code);
            if (entry != null) {
                if (Instant.now().isBefore(entry.expiresAt)) {
                    return entry.link;
                }
                cache.remove(code);
            }
            Optional<ShortLink> link = store.findByCode(code);
            cache.put(code, new CacheEntry(link, Instant.now().plus(ttl)));
            return link;
        }
    }

    @Override
    public int cachedEntries() {
        synchronized (lock) {
            cache.removeExpired();
            return cache.size();
        }
    }

    @Override
    public void invalidate(String code) {
        synchronized (lock) {
            cache.remove(code);
        }
    }

    private static final class LruCache extends LinkedHashMap<String, CacheEntry> {

        private static final long serialVersionUID = 1L;

        private final int maxSize;

        private LruCache(int maxSize) {
            super(16, 0.75f, true);
            this.maxSize = maxSize;
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<String, CacheEntry> eldest) {
            return size() > maxSize;
        }

        private void removeExpired() {
            Instant now = Instant.now();
            Iterator<Map.Entry<String, CacheEntry>> iterator = entrySet().iterator();
            while (iterator.hasNext()) {
                Map.Entry<String, CacheEntry> next = iterator.next();
                if (!now.isBefore(next.getValue().expiresAt)) {
                    iterator.remove();
                }
            }
        }
    }

    private static final class CacheEntry {

        private final Optional<ShortLink> link;

        private final Instant expiresAt;

        private CacheEntry(Optional<ShortLink> link, Instant expiresAt) {
            this.link = link;
            this.expiresAt = expiresAt;
        }
    }
}
