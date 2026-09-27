package com.lab.shortlink.resolve;

import com.lab.shortlink.link.ShortLink;
import java.util.Optional;

public interface LinkResolver {

    Optional<ShortLink> resolve(String code);

    int cachedEntries();

    /**
     * 在写路径上主动失效指定短码的缓存条目。
     *
     * <p>对不带缓存的解析器，默认实现为空操作。
     */
    default void invalidate(String code) {
        // no-op for resolvers that do not cache
    }
}
