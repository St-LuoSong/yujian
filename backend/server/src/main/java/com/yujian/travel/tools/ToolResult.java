package com.yujian.travel.tools;

import java.time.Instant;
import java.time.temporal.ChronoUnit;

public record ToolResult<T>(
    T data,
    String source,
    Instant queriedAt,
    boolean isRealtime,
    boolean isCached,
    boolean isMock,
    Instant expiresAt,
    String errorCode,
    String errorMessage) {

    public static <T> ToolResult<T> mock(T data, String source) {
        Instant now = Instant.now();
        return new ToolResult<>(data, source, now, false, false, true,
            now.plus(1, ChronoUnit.HOURS), null, null);
    }

    /** 系统自有资料（内容库、景区公开资料），既不是实时接口也不是演示数据。 */
    public static <T> ToolResult<T> reference(T data, String source) {
        Instant now = Instant.now();
        return new ToolResult<>(data, source, now, false, false, false,
            now.plus(24, ChronoUnit.HOURS), null, null);
    }

    /** 真实外部接口返回的数据，expiresAt 决定缓存有效期。 */
    public static <T> ToolResult<T> realtime(T data, String source, Instant expiresAt) {
        return new ToolResult<>(data, source, Instant.now(), true, false, false, expiresAt, null, null);
    }

    /**
     * 真实数据源不可用时的降级结果。
     *
     * 数据本身可用，但会被明确标记成演示数据并带上 errorCode，
     * 使工具轨迹、运营统计和用户提示都能看到"这里降级了"。
     */
    public static <T> ToolResult<T> degraded(T data, String source, String errorCode, String errorMessage) {
        Instant now = Instant.now();
        return new ToolResult<>(data, source, now, false, false, true,
            now.plus(1, ChronoUnit.HOURS), errorCode, errorMessage);
    }

    public static <T> ToolResult<T> cached(T data, String source, Instant expiresAt) {
        Instant now = Instant.now();
        return new ToolResult<>(data, source, now, false, true, false,
            expiresAt, null, null);
    }

    public static <T> ToolResult<T> error(String source, String errorCode, String errorMessage) {
        return new ToolResult<>(null, source, Instant.now(), false, false, false,
            null, errorCode, errorMessage);
    }

    public boolean success() {
        return errorCode == null;
    }

    /**
     * 用户可见的来源标签，也是客户端 `DataStatus.fromServer` 的唯一解析入口。
     *
     * 顺序不能改：降级结果同时满足 isMock 与 errorCode != null，
     * 必须排在纯演示数据之前，否则"取不到真实数据"这件事会被显示成普通的演示数据。
     */
    public String dataStatus() {
        if (isRealtime) {
            return "实时数据";
        }
        if (isCached) {
            return "缓存数据";
        }
        if (isMock) {
            return errorCode == null ? "演示数据" : "演示数据（降级）";
        }
        return "系统资料";
    }
}
