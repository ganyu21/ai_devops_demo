package com.lab.shortlink.resolve;

import static org.assertj.core.api.Assertions.assertThat;

import com.lab.shortlink.link.LinkStore;
import com.lab.shortlink.link.ShortLink;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class CachingLinkResolverTest {

    /** 记录底层被真查了几次的替身，用来证明缓存确实生效。 */
    private static final class CountingLinkStore implements LinkStore {

        private final Map<String, ShortLink> links = new HashMap<>();

        private int lookups;

        @Override
        public Optional<ShortLink> findByCode(String code) {
            lookups++;
            return Optional.ofNullable(links.get(code));
        }

        @Override
        public void save(ShortLink link) {
            links.put(link.code(), link);
        }

        @Override
        public int size() {
            return links.size();
        }
    }

    private final CountingLinkStore store = new CountingLinkStore();

    private final CachingLinkResolver resolver = new CachingLinkResolver(store);

    @Test
    void repeatedResolvesHitTheStoreOnlyOnce() {
        store.save(new ShortLink("Aa11Bb22", "https://example.com/target", Instant.now()));

        assertThat(resolver.resolve("Aa11Bb22")).isPresent();
        assertThat(resolver.resolve("Aa11Bb22")).isPresent();
        assertThat(resolver.resolve("Aa11Bb22")).isPresent();

        assertThat(store.lookups).isEqualTo(1);
    }

    @Test
    void aMissIsCachedToo() {
        assertThat(resolver.resolve("NoSuchCode")).isEmpty();
        assertThat(resolver.resolve("NoSuchCode")).isEmpty();

        assertThat(store.lookups).isEqualTo(1);
    }

    @Test
    void resolveReturnsTheStoredTargetUrl() {
        store.save(new ShortLink("Cc33Dd44", "https://example.com/deep/path", Instant.now()));

        assertThat(resolver.resolve("Cc33Dd44"))
                .get()
                .extracting(ShortLink::targetUrl)
                .isEqualTo("https://example.com/deep/path");
    }

    @Test
    void cachedEntriesCountsDistinctResolvedCodes() {
        store.save(new ShortLink("Aa11Bb22", "https://example.com/a", Instant.now()));

        resolver.resolve("Aa11Bb22");
        resolver.resolve("Aa11Bb22");
        resolver.resolve("Unknown1");

        assertThat(resolver.cachedEntries()).isEqualTo(2);
    }
}
