package com.yujian.travel.service;

/**
 * 把要落库的文本收进实体声明的列宽里。
 *
 * 起因是一次真实故障：模型把"建议上午出发，具体车次以铁路官方为准"写进了
 * `time` 字段，而那一列是 VARCHAR(16)。一次本该成功的生成于是变成 500，
 * 用户什么都没拿到。
 *
 * 字段语义的纠正放在解析层（时间必须是 HH:mm），这里只做**兜底**：
 * 模型输出长度不可控，任何一次写入都不该因为多几个字就让整份方案失败。
 * 宁可截断一个字段，也不要 500。
 */
public final class ColumnText {

    private ColumnText() {
    }

    /** 放得下就原样返回，放不下就截断；null 原样返回。 */
    public static String clamp(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        int end = Math.max(0, maxLength);
        // 不要把代理对（emoji 等）从中间截开，否则会得到半个非法字符。
        if (end > 0 && Character.isHighSurrogate(value.charAt(end - 1))) {
            end--;
        }
        return value.substring(0, end);
    }
}
