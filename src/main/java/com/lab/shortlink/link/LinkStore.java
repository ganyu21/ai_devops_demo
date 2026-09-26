package com.lab.shortlink.link;

import java.util.Optional;

public interface LinkStore {

    Optional<ShortLink> findByCode(String code);

    void save(ShortLink link);

    int size();
}
