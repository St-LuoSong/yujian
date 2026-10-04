package com.yujian.travel.api;

import java.util.List;
import java.util.Map;

public final class SecurityModels {
    private SecurityModels() {
    }

    /**
     * 一个可调项。
     *
     * 默认值、范围、单位、说明都来自服务端的登记表，而不是前端写死 ——
     * 否则改了默认值之后界面上还显示旧数字，运营会以为自己没保存成功。
     */
    public record SettingItem(
        String key,
        String group,
        String label,
        long value,
        long defaultValue,
        long min,
        long max,
        String unit,
        String description
    ) {
    }

    /** 某个外部工具组今天用了多少。 */
    public record QuotaUsage(String group, String label, long limit, long used) {
        public long remaining() {
            return Math.max(0, limit - used);
        }
    }

    public record LimitsView(List<SettingItem> items, List<QuotaUsage> quotas,
                             int activeWindows) {
    }

    public record UpdateLimitsRequest(Map<String, Long> values) {
    }
}
