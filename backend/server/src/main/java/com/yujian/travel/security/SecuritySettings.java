package com.yujian.travel.security;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * 可调安全参数的登记表。
 *
 * 只有登记在这里的键才能被写入 —— 没有白名单的话，`app_setting` 迟早会变成
 * 一张"谁都能塞点什么进去"的表，而排障时没人知道哪个键是真的有用。
 *
 * 这里同时是 admin 界面的数据来源：标签、分组、取值范围、默认值都来自同一份
 * 定义，避免"后端改了默认值、前端还写死旧的"这种对不上的情况。
 */
public final class SecuritySettings {
    private SecuritySettings() {
    }

    /** 限流总开关。关掉之后所有桶都不再拦截（排障时用）。 */
    public static final String RATE_ENABLED = "rate.enabled";

    public static final String QUOTA_ENABLED = "quota.enabled";

    /** 一个限流桶：窗口长度 + 窗口内允许的次数。 */
    public record Bucket(String name, String label, long defaultLimit, long defaultWindowSeconds,
                         String description) {
        public String limitKey() {
            return "rate." + name + ".limit";
        }

        public String windowKey() {
            return "rate." + name + ".window";
        }
    }

    /**
     * 六个桶。
     *
     * `plan-daily` 是唯一一个长窗口：它的作用不是防刷，而是给大模型开销兜底 ——
     * 每分钟 20 次可能一秒钟就用完，但一天 60 次是实打实的成本上限。
     */
    public static final List<Bucket> BUCKETS = List.of(
        new Bucket("auth", "登录 / 注册 / 验证码", 10, 60,
            "防止撞库与短信轰炸"),
        new Bucket("plan", "生成与调整行程", 20, 60,
            "防止一次会话里连点生成"),
        new Bucket("plan-daily", "每人每日规划次数", 60, 86400,
            "大模型开销的硬上限，按自然日重置"),
        new Bucket("media", "图片上传", 30, 60,
            "上传会落盘并重编码，比普通请求贵得多"),
        new Bucket("write", "其他写操作", 60, 60,
            "点赞、收藏、评论等"),
        new Bucket("read", "读接口", 300, 60,
            "正常浏览远到不了这个数"));

    /** 一个外部工具配额组：同一套上游的多个工具共用一个额度。 */
    public record QuotaGroup(String name, String label, String toolPrefix,
                             List<String> toolNames, long defaultValue, String description) {
        public String key() {
            return "quota." + name + ".daily";
        }
    }

    /**
     * 三个配额组。
     *
     * 12306 的三个工具（余票 / 票价 / 中转）打的是同一套上游，共用一个额度；
     * 分三个额度只会让"到底还能查几次"变得说不清。
     */
    public static final List<QuotaGroup> QUOTA_GROUPS = List.of(
        new QuotaGroup("weather", "天气（Open-Meteo）", "getweather", List.of(), 500,
            "一次规划按天数各查一次"),
        new QuotaGroup("route", "路线（百度地图）", "getroute", List.of(), 300,
            "百度地图 Web 服务有免费配额"),
        new QuotaGroup("rail", "车次与票价（12306）", null,
            List.of("searchtrain", "quoterailfares", "searchtransfer"), 300,
            "余票、票价、中转共用；12306 对频率敏感"));

    public record Definition(String key, String group, String label, long defaultValue,
                             long min, long max, String unit, String description) {
    }

    /** 全部登记项。管理台读的就是这一份。 */
    public static List<Definition> definitions() {
        List<Definition> all = new ArrayList<>();
        all.add(new Definition(RATE_ENABLED, "rate", "接口限流总开关", 1, 0, 1, "",
            "0 = 关闭全部限流（仅排障时使用）"));
        for (Bucket bucket : BUCKETS) {
            all.add(new Definition(bucket.limitKey(), "rate", bucket.label() + " · 次数",
                bucket.defaultLimit(), 1, 100000, "次", bucket.description()));
            all.add(new Definition(bucket.windowKey(), "rate", bucket.label() + " · 窗口",
                bucket.defaultWindowSeconds(), 1, 604800, "秒", "窗口内超过次数即拒绝"));
        }
        all.add(new Definition(QUOTA_ENABLED, "quota", "外部工具配额总开关", 1, 0, 1, "",
            "0 = 不限制外部调用（不推荐）"));
        for (QuotaGroup group : QUOTA_GROUPS) {
            all.add(new Definition(group.key(), "quota", group.label() + " · 每日上限",
                group.defaultValue(), 1, 100000, "次", group.description()));
        }
        return List.copyOf(all);
    }

    public static Optional<Definition> find(String key) {
        String normalized = key == null ? "" : key.trim().toLowerCase(Locale.ROOT);
        return definitions().stream()
            .filter(definition -> definition.key().equals(normalized))
            .findFirst();
    }
}
