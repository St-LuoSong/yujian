package com.yujian.travel.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Getter
@Setter
@ConfigurationProperties(prefix = "app")
public class AppProperties {
    private String mode = "mock";
    private int trialLimit = 1;
    private final Cors cors = new Cors();
    private final Jwt jwt = new Jwt();
    private final Smtp smtp = new Smtp();
    private final Llm llm = new Llm();
    private final Share share = new Share();
    private final Media media = new Media();
    private final AppRelease appRelease = new AppRelease();
    private final Tools tools = new Tools();
    private final Admin admin = new Admin();

    @Getter
    @Setter
    public static class Cors {
        private List<String> allowedOrigins = List.of("http://localhost:5173");
    }

    @Getter
    @Setter
    public static class Jwt {
        private String secret = "yujian-travel-dev-secret-key-2026";
        private long accessMinutes = 120;
        private long refreshDays = 7;
    }

    @Getter
    @Setter
    public static class Smtp {
        private boolean enabled;
        private String from = "no-reply@yujian.local";
        private boolean mockCodeLog = true;
        private long codeMinutes = 10;
        private long resendSeconds = 60;
        private int maxAttempts = 5;
    }

    @Getter
    @Setter
    public static class Llm {
        /** Global switch. Individual vendors are enabled separately. */
        private boolean enabled;

        /** Defaults inherited by every vendor that does not override them. */
        private double temperature = 0.3;
        private int timeoutSeconds = 60;

        /**
         * One entry per vendor. The map key is the provider id that appears in
         * traces and in the admin console, for example {@code openai} or
         * {@code deepseek}.
         *
         * All four supported vendors speak the OpenAI chat completions shape,
         * so one engine implementation serves them and the difference lives in
         * configuration rather than in code.
         */
        private Map<String, Provider> providers = new LinkedHashMap<>();
    }

    @Getter
    @Setter
    public static class Provider {
        private boolean enabled;
        private String displayName = "";

        /**
         * API root including the version segment, for example
         * {@code https://api.deepseek.com/v1}. The chat path is appended to it.
         */
        private String baseUrl = "";
        private String apiKey = "";
        private String model = "";

        /** Lower runs first when several vendors are enabled. */
        private int priority = 100;

        /** Optional per vendor overrides; null inherits the global value. */
        private Double temperature;
        private Integer timeoutSeconds;
    }

    @Getter
    @Setter
    public static class Share {
        private String baseUrl = "http://localhost:8080/share";
        private int defaultExpireDays = 7;
    }

    /**
     * 运营台图片上传。
     *
     * 存储在服务端本地目录，通过只读的 /media/** 对外提供；上传接口本身在
     * /api/admin/** 之下，因此只有 ADMIN 能写入。
     */
    @Getter
    @Setter
    public static class Media {
        /** 上传目录。相对路径按服务端工作目录（server/）解析。 */
        private String storageDir = "./data/uploads";

        /**
         * 对外可访问的媒体根地址，例如 http://10.0.2.2:8080。
         * 留空时按上传请求的 scheme/host 推导，适合本地开发；
         * 模拟器或反向代理场景建议显式配置。
         */
        private String baseUrl = "";

        private long maxSizeMb = 8;

        /** 单个方向的像素上限，用于拒绝解压后过大的图片。 */
        private int maxDimension = 6000;
    }

    /** Trusted Android release channel. APK files are never served from /media. */
    @Getter
    @Setter
    public static class AppRelease {
        private String storageDir = "./data/releases";
        private String expectedPackageName = "com.yujian.travel";
        private List<String> allowedCertificateSha256 = List.of();
        private long maxSizeMb = 300;

        /**
         * 允许落后的最大版本跨度。
         *
         * 超过这个跨度就不再问用户"要不要升级"，而是直接强制更新。理由很实际：
         * 落后十几个版本的用户手上那份 APK，接口契约、数据状态语义甚至登录流程
         * 都可能跟服务端对不上了，让他继续用下去只会不断地"报错—重启—再报错"。
         *
         * 5 是给比赛演示用的默认值：既不会因为一次小改动就强制所有人升级，
         * 又能在演示"版本差过大"这条规则时真的触发。
         */
        private int forcedUpdateGap = 5;

        /**
         * 老客户端的版本检查是否允许回落到调试通道。
         *
         * v0.4.0 及以前的客户端根本不知道"通道"这回事，请求里不带 channel。
         * 它们只能被当成正式通道查询，于是永远看不到只发布了调试包的新版本 ——
         * 用户手上那份 APK 就被锁死了，只能手动重装。
         *
         * 打开这个开关后：没带 channel 的请求先查正式通道，正式通道没有已发布版本
         * 时才回落到调试通道。等所有在用的客户端都升级到会带 channel 的版本之后，
         * 应该把它关掉。
         */
        private boolean legacyCheckFallsBackToDebug = true;
    }

    /**
     * 外部工具（地图 / 天气 / 铁路）的数据源配置。
     *
     * 原则：能取到真实数据就用真实数据并如实标注，取不到就降级到本地演示数据，
     * 同时把降级原因写进 warnings 与工具轨迹 —— 不允许把演示数据说成实时数据。
     */
    @Getter
    @Setter
    public static class Tools {
        /** live：优先真实数据源，失败降级；mock：全部使用本地演示数据（离线演示用）。 */
        private String mode = "live";

        /** 单次外部调用的超时时间。取得太长会拖慢规划，取得太短会频繁降级。 */
        private int timeoutSeconds = 4;

        private final Baidu baidu = new Baidu();
        private final Weather weather = new Weather();
        private final Railway railway = new Railway();
        private final Ticket ticket = new Ticket();
    }

    @Getter
    @Setter
    public static class Baidu {
        /** 百度地图开放平台 AK。为空时路线规划与底图直接降级，不会发起网络请求。 */
        private String apiKey = "";

        /** 百度地图 Web 服务域名，保留可替换空间（例如代理网关）。 */
        private String baseUrl = "https://api.map.baidu.com";

        /**
         * 静态底图接口路径。
         *
         * 底图走"服务端取图再转发"的路线，AK 因此不必下发到 APK；
         * 单独抽成配置是为了换接口版本或改走自建代理时不用动代码。
         */
        private String staticMapPath = "/staticimage/v2";

        /** 底图缓存分钟数。底图按天级别更新，缓存久一点能省下大量配额。 */
        private int mapCacheMinutes = 720;

        /** 底图像素尺寸默认值，客户端请求会被收窄到 320~1024 之间。 */
        private int mapWidth = 1024;
        private int mapHeight = 768;

        /** 底图是二进制大响应，超时比 JSON 工具宽松一些。 */
        private int mapTimeoutSeconds = 8;

        /** 一天行程最多画几个点，避免一次规划把配额打光，也避免地图糊成一团。 */
        private int mapMaxMarkers = 12;

        /**
         * 地理编码可信度的兜底下限（0-100）。
         *
         * 百度对"乡镇级"景点（白马寺、龙门石窟）只给 25 分，
         * 真正区分"认得这个地方"与"只认得城市"的是 level，不是这个分数。
         * 因此 level 才是主判据（城市/区县一律不画），这里只兜住明显异常的响应。
         * 低可信度的点不画在地图上，而是列进"未定位"清单：
         * 宁可少画一个点，也不要把一个不相关的位置说成是行程里的那一站。
         */
        private int mapMinConfidence = 20;
    }

    @Getter
    @Setter
    public static class Weather {
        /** open-meteo：免费且无需密钥，可直接验证；none：只用本地演示数据。 */
        private String provider = "open-meteo";

        private String baseUrl = "https://api.open-meteo.com";

        /** 天气变化快，缓存时间要短。 */
        private int cacheMinutes = 30;
    }

    @Getter
    @Setter
    public static class Railway {
        /**
         * 12306-mcp：调用独立部署的 mcp-server-12306 查实时车次与余票（推荐）；
         * reference：内置参考时刻表，明确标注为非实时。
         *
         * 两种模式都不抓取 12306 网页、不保存证件信息、不代购，购票一律引导到官方渠道。
         */
        private String provider = "reference";

        /** mcp-server-12306 的 Streamable HTTP 入口，例如 http://localhost:8000/mcp。 */
        private String mcpUrl = "";

        /** 余票变化快，实时车次必须短缓存；只有参考时刻表才适合长缓存。 */
        private int cacheMinutes = 30;
    }

    /**
     * 门票价格。
     *
     * 价格属于"会影响用户决策、又最容易过期"的数据，所以单独成一个端口：
     * catalog 用景区内容库里运营维护的参考价，smart-buy 预留给外部比价服务。
     * 无论哪种来源，都必须如实标注，不允许把参考价说成实时票价。
     */
    @Getter
    @Setter
    public static class Ticket {
        private String provider = "catalog";

        /** 外部比价服务地址；留空时按未配置处理并降级到内容库参考价。 */
        private String baseUrl = "";
    }

    /**
     * Optional bootstrap operator account.
     *
     * Empty by default, so a fresh deployment has no privileged account until
     * an operator sets the environment variables.
     */
    @Getter
    @Setter
    public static class Admin {
        private String username = "";
        private String password = "";
        private String email = "";
    }
}
