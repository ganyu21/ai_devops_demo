package com.lab.shortlink.code;

import java.security.SecureRandom;
import org.springframework.stereotype.Component;

/**
 * 短码生成器。
 *
 * <p>短码会出现在公开可访问的 URL 里，能被枚举出来就等于能遍历别人创建的链接。
 * 因此长度与字母表是<b>不可协商的安全约束</b>：{@value #CODE_LENGTH} 位 base62，
 * 至少 47 bit 熵。这条约束由三处共同固定 —— 本类的 javadoc、
 * {@code ShortCodeGeneratorTest} 里的策略断言、以及需求单的「约束」节。
 * 任何改动都必须走需求评审，并同步更新那三处。
 */
@Component
public class ShortCodeGenerator {

    /** 短码长度，见类注释。 */
    public static final int CODE_LENGTH = 8;

    private static final char[] BASE62 =
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".toCharArray();

    private final SecureRandom random = new SecureRandom();

    public String next() {
        char[] code = new char[CODE_LENGTH];
        for (int i = 0; i < code.length; i++) {
            code[i] = BASE62[random.nextInt(BASE62.length)];
        }
        return new String(code);
    }
}
