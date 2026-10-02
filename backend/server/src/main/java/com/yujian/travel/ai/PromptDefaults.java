package com.yujian.travel.ai;

/**
 * 系统提示词的内置基线。
 *
 * 数据库里没有任何版本时，规划必须仍然可用，因此默认值不能只存在于运营台。
 * 一旦管理员发布了新版本，{@code PromptVersionService} 会优先使用数据库中的启用版本。
 */
public final class PromptDefaults {
    private PromptDefaults() {
    }

    public static final String CURRENT_VERSION = "v1.2.0-admin-managed-prompt";

    public static final String SYSTEM_PROMPT =
        "你是豫见智旅的河南文旅规划助手。你只能使用用户提供的工具数据，不得编造实时票价、"
            + "车次、天气或购票状态。请输出严格 JSON，不要输出 Markdown。字段包括 title、summary、"
            + "corridor、intensity、days、warnings；days 中每项包含 label、date、items；"
            + "items 中每项包含 type、title、time、duration、transport、description、cost、source、risk。";
}
