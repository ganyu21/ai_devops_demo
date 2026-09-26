package com.lab.shortlink.code;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashSet;
import java.util.Set;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

class ShortCodeGeneratorTest {

    private static final Pattern BASE62 = Pattern.compile("^[0-9A-Za-z]+$");

    private final ShortCodeGenerator generator = new ShortCodeGenerator();

    /**
     * 这条断言把「短码不可枚举」这个安全要求编码成了机器可检查的形式。
     * 长度写死为 8 而不是引用 {@link ShortCodeGenerator#CODE_LENGTH}：
     * 引用常量会让这条断言在常量被改小时跟着一起变绿，那正是它要挡住的事。
     */
    @Test
    void codeLengthAndAlphabetMeetTheUnenumerabilityPolicy() {
        String code = generator.next();

        assertEquals(8, code.length(),
                "policy requires 8 base62 characters, i.e. at least 47 bits of entropy");
        assertTrue(BASE62.matcher(code).matches(),
                "policy requires the base62 alphabet only, but got: " + code);
    }

    @Test
    void generatedCodeLengthFollowsTheDeclaredConstant() {
        for (int i = 0; i < 200; i++) {
            assertEquals(ShortCodeGenerator.CODE_LENGTH, generator.next().length());
        }
    }

    @Test
    void consecutiveDrawsDoNotCollide() {
        Set<String> codes = new HashSet<>();
        for (int i = 0; i < 5000; i++) {
            codes.add(generator.next());
        }

        assertEquals(5000, codes.size(), "5000 draws produced a duplicate, the generator is not random enough");
    }
}
