package com.lab.shortlink.resolve;

import com.lab.shortlink.link.ShortLink;
import java.util.Optional;

public interface LinkResolver {

    Optional<ShortLink> resolve(String code);

    int cachedEntries();
}
