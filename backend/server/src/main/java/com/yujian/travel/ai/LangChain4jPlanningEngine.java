package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import dev.langchain4j.model.chat.ChatLanguageModel;
import dev.langchain4j.model.openai.OpenAiChatModel;

import java.time.Duration;

/**
 * One vendor endpoint, reached through LangChain4j.
 *
 * OpenAI, DeepSeek, Kimi and Qwen all expose the OpenAI chat completions shape,
 * so a single implementation serves every vendor and the difference lives in
 * {@link LlmProvider}. The model client is created lazily and reused, because
 * building it per request would re-open the HTTP client every time.
 */
public class LangChain4jPlanningEngine implements PlanningEngine {
    private static final int MIN_TIMEOUT_SECONDS = 10;

    /** 一份 1—3 天的行程 JSON 远小于这个值，留足余量避免被截断。 */
    private static final int MAX_OUTPUT_TOKENS = 4096;

    private final LlmProvider provider;
    private final PlanningPromptFactory promptFactory;
    private final LlmPlanParser planParser;
    private volatile ChatLanguageModel model;

    public LangChain4jPlanningEngine(LlmProvider provider, PlanningPromptFactory promptFactory,
                                     LlmPlanParser planParser) {
        this.provider = provider;
        this.promptFactory = promptFactory;
        this.planParser = planParser;
    }

    /** The vendor id, for example {@code deepseek}. */
    @Override
    public String name() {
        return provider.id();
    }

    @Override
    public boolean available() {
        return provider.configured();
    }

    @Override
    public TravelModels.TripPlan generate(PlanningContext context) {
        if (!available()) {
            throw new IllegalStateException("供应商 " + provider.displayName() + " 未配置");
        }
        String content = model().generate(promptFactory.completePrompt(context));
        return planParser.parse(content, context.request());
    }

    private ChatLanguageModel model() {
        ChatLanguageModel current = model;
        if (current == null) {
            synchronized (this) {
                current = model;
                if (current == null) {
                    current = OpenAiChatModel.builder()
                        .baseUrl(provider.baseUrl())
                        .apiKey(provider.apiKey())
                        .modelName(provider.model())
                        .temperature(provider.temperature())
                        // 明确上限，让四家厂商的输出长度行为一致；不设的话各家默认值不同，
                        // 行程 JSON 可能被截断，表现成"JSON 无法解析"这种误导性错误。
                        .maxTokens(MAX_OUTPUT_TOKENS)
                        .timeout(Duration.ofSeconds(Math.max(MIN_TIMEOUT_SECONDS, provider.timeoutSeconds())))
                        .maxRetries(1)
                        .logRequests(false)
                        .logResponses(false)
                        .build();
                    model = current;
                }
            }
        }
        return current;
    }
}
