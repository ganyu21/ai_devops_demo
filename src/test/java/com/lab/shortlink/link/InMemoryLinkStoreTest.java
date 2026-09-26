package com.lab.shortlink.link;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import org.junit.jupiter.api.Test;

class InMemoryLinkStoreTest {

    private final InMemoryLinkStore store = new InMemoryLinkStore();

    @Test
    void savedLinkCanBeFoundByItsCode() {
        Instant createdAt = Instant.parse("2026-01-01T00:00:00Z");
        store.save(new ShortLink("Ab12Cd34", "https://example.com/target", createdAt));

        assertThat(store.findByCode("Ab12Cd34"))
                .contains(new ShortLink("Ab12Cd34", "https://example.com/target", createdAt));
    }

    @Test
    void unknownCodeResolvesToEmpty() {
        assertThat(store.findByCode("NoSuchCode")).isEmpty();
    }

    @Test
    void savingTheSameCodeTwiceKeepsTheLatestTarget() {
        store.save(new ShortLink("Ab12Cd34", "https://example.com/first", Instant.now()));
        store.save(new ShortLink("Ab12Cd34", "https://example.com/second", Instant.now()));

        assertThat(store.findByCode("Ab12Cd34"))
                .get()
                .extracting(ShortLink::targetUrl)
                .isEqualTo("https://example.com/second");
        assertThat(store.size()).isEqualTo(1);
    }

    @Test
    void sizeCountsDistinctCodesOnly() {
        store.save(new ShortLink("Aa11Bb22", "https://example.com/a", Instant.now()));
        store.save(new ShortLink("Cc33Dd44", "https://example.com/b", Instant.now()));
        store.save(new ShortLink("Aa11Bb22", "https://example.com/a-corrected", Instant.now()));

        assertThat(store.size()).isEqualTo(2);
    }
}
