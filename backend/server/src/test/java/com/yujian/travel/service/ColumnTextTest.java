package com.yujian.travel.service;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 列宽兜底的行为约束。
 *
 * 这一层存在的唯一理由，是模型输出长度不可控：一次超长字符串不该让
 * "生成方案"变成 500。它只负责截断，不负责纠正字段语义。
 */
class ColumnTextTest {

    @Test
    void keepsValuesThatAlreadyFit() {
        assertThat(ColumnText.clamp("洛阳", 16)).isEqualTo("洛阳");
        assertThat(ColumnText.clamp("", 16)).isEmpty();
    }

    @Test
    void passesNullThrough() {
        assertThat(ColumnText.clamp(null, 16)).isNull();
    }

    @Test
    void truncatesToTheColumnLength() {
        String tooLong = "建议上午出发，具体车次以铁路官方为准";
        String clamped = ColumnText.clamp(tooLong, 16);

        assertThat(clamped).hasSize(16);
        assertThat(tooLong).startsWith(clamped);
    }

    @Test
    void neverSplitsASurrogatePair() {
        // 每个 emoji 占两个 char，限长 5 时第 5 个 char 是半个代理对。
        String emoji = "洛阳龙门石窟😀😀";
        String clamped = ColumnText.clamp(emoji, 5);

        // 逐字符配对检查：不允许出现落单的高/低代理。
        boolean paired = true;
        for (int i = 0; i < clamped.length(); i++) {
            char current = clamped.charAt(i);
            if (Character.isHighSurrogate(current)) {
                if (i + 1 >= clamped.length() || !Character.isLowSurrogate(clamped.charAt(i + 1))) {
                    paired = false;
                    break;
                }
                i++;
            } else if (Character.isLowSurrogate(current)) {
                paired = false;
                break;
            }
        }
        assertThat(paired).isTrue();
    }
}
