package com.yujian.travel.tools;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 一次规划里所有外部依据的汇总。
 *
 * results 是给业务用的数据，inputs 是可追溯的调用参数，warnings 是给用户看的如实提示。
 * 计数方法供编排层、校验层与运营统计复用，避免各处各算一套口径。
 */
public record ToolCollection(UUID correlationId, Map<String, ToolResult<?>> results,
                             Map<String, String> inputs, List<String> warnings, long durationMs) {

    /** 演示数据（含因外部数据源不可用而降级的演示数据）。 */
    public int mockCount() {
        return (int) results.values().stream().filter(ToolResult::isMock).count();
    }

    /** 其中带 errorCode 的那部分：真实数据源取不到、被兜底顶上的结果。 */
    public int degradedCount() {
        return (int) results.values().stream()
            .filter(result -> result.isMock() && result.errorCode() != null)
            .count();
    }

    public int realtimeCount() {
        return (int) results.values().stream().filter(ToolResult::isRealtime).count();
    }

    /** 连兜底数据都没有的失败项。 */
    public int errorCount() {
        return (int) results.values().stream().filter(result -> result.data() == null).count();
    }
}

