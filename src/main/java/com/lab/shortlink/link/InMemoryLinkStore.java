package com.lab.shortlink.link;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.springframework.stereotype.Repository;

@Repository
public class InMemoryLinkStore implements LinkStore {

    private final ConcurrentMap<String, ShortLink> links = new ConcurrentHashMap<>();

    @Override
    public Optional<ShortLink> findByCode(String code) {
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
