package com.yujian.travel.ai;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.api.TravelModels;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 解析器的验收对象不是"标准 JSON"，而是**真实模型实际会返回的东西**。
 *
 * 这组用例来自一次真实故障：DeepSeek 调用成功、耗时 6 秒，但整份方案被判为
 * "LLM 返回的行程 JSON 无法解析"，于是降级成 Mock，用户看到"AI 降级"。
 * 原因不是模型答错，而是解析器用了严格对象绑定，模型把费用写成 `"约120元"`
 * 之类的自然表达就直接失败。下面每个用例都对应一种真实会出现的写法。
 */
class LlmPlanParserTest {

    private final LlmPlanParser parser = new LlmPlanParser(new ObjectMapper());

    private final TravelModels.PlanRequest request = new TravelModels.PlanRequest(
        "郑州到洛阳两天", "2026-10-02", "郑州", "洛阳", 2, 2, 1000, "历史文化", "轻松", "高铁");

    @Test
    void parsesPlainJson() {
        String json = """
            {
              "title": "洛阳两日",
              "summary": "沿着伊河读懂中原",
              "corridor": "郑州—洛阳",
              "intensity": "适中",
              "days": [
                {
                  "label": "DAY 1",
                  "date": "10-03",
                  "items": [
                    {"type": "景点", "title": "龙门石窟", "time": "09:00", "cost": 90}
                  ]
                }
              ],
              "warnings": ["门票为参考价"]
            }
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.title()).isEqualTo("洛阳两日");
        assertThat(plan.corridor()).isEqualTo("郑州—洛阳");
        assertThat(plan.days()).hasSize(1);
        assertThat(plan.days().get(0).items()).hasSize(1);
        assertThat(plan.days().get(0).items().get(0).title()).isEqualTo("龙门石窟");
        assertThat(plan.totalCost()).isEqualTo(90);
        assertThat(plan.perPersonCost()).isEqualTo(45);
        assertThat(plan.warnings()).containsExactly("门票为参考价");
        assertThat(plan.dataStatus()).isEqualTo("AI 生成");
    }

    @Test
    void acceptsMarkdownFenceWithProseAroundIt() {
        String content = """
            好的，下面是我为你规划的行程：

            ```json
            {
              "title": "洛阳两日",
              "days": [{"label": "DAY 1", "items": [{"title": "龙门石窟", "cost": 90}]}]
            }
            ```

            需要我调整节奏吗？
            """;

        TravelModels.TripPlan plan = parser.parse(content, request);

        assertThat(plan.title()).isEqualTo("洛阳两日");
        assertThat(plan.days()).hasSize(1);
    }

    @Test
    void readsCostFromNaturalLanguage() {
        String json = """
            {
              "title": "预算测试",
              "days": [
                {"label": "DAY 1", "items": [
                  {"title": "龙门石窟", "cost": "约120元"},
                  {"title": "洛阳博物馆", "cost": "免费"},
                  {"title": "高铁", "cost": 174.0}
                ]}
              ]
            }
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.days().get(0).items()).extracting(TravelModels.TripItem::cost)
            .containsExactly(120, 0, 174);
        assertThat(plan.totalCost()).isEqualTo(294);
    }

    @Test
    void acceptsWarningsAsASingleSentence() {
        String json = """
            {
              "title": "提醒测试",
              "days": [{"label": "DAY 1", "items": [{"title": "龙门石窟", "cost": 90}]}],
              "warnings": "门票价格仅供参考，请以官方渠道为准"
            }
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.warnings()).containsExactly("门票价格仅供参考，请以官方渠道为准");
    }

    @Test
    void toleratesTrailingCommas() {
        String json = """
            {
              "title": "逗号测试",
              "days": [
                {"label": "DAY 1", "items": [
                  {"title": "龙门石窟", "cost": 90},
                ]},
              ],
            }
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.days()).hasSize(1);
        assertThat(plan.days().get(0).items()).hasSize(1);
    }

    @Test
    void fillsDefaultsForMissingOptionalFields() {
        String json = """
            {"days": [{"items": [{"title": "白马寺"}]}]}
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.title()).isEqualTo("河南 AI 行程");
        assertThat(plan.intensity()).isEqualTo("适中");
        assertThat(plan.days().get(0).label()).isEqualTo("DAY 1");
        assertThat(plan.days().get(0).items().get(0).time()).isEqualTo("09:00");
        assertThat(plan.days().get(0).items().get(0).source()).isEqualTo("AI 生成");
        assertThat(plan.warnings()).isEmpty();
    }

    @Test
    void keepsPerPersonCostAtLeastOne() {
        String json = """
            {"days": [{"items": [{"title": "免费步行街", "cost": 0}]}]}
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.totalCost()).isZero();
        assertThat(plan.perPersonCost()).isEqualTo(1);
    }

    @Test
    void fallsBackToTwoTravelersWhenRequestOmitsThem() {
        TravelModels.PlanRequest anonymous =
            new TravelModels.PlanRequest("一句话", null, null, null, null, null, null, null, null, null);
        String json = """
            {"days": [{"items": [{"title": "龙门石窟", "cost": 100}]}]}
            """;

        TravelModels.TripPlan plan = parser.parse(json, anonymous);

        assertThat(plan.perPersonCost()).isEqualTo(50);
    }

    @Test
    void turnsAProseTimeFieldIntoAClockValue() {
        String json = """
            {"days": [{"items": [
              {"title": "出发", "time": "建议上午出发，具体车次以铁路官方为准", "cost": 0},
              {"title": "龙门石窟", "time": "9:5", "cost": 90},
              {"title": "晚餐", "time": "18:30 左右", "cost": 60}
            ]}]}
            """;

        TravelModels.TripPlan plan = parser.parse(json, request);

        assertThat(plan.days().get(0).items()).extracting(TravelModels.TripItem::time)
            .containsExactly("09:00", "09:05", "18:30");
    }

    @Test
    void rejectsTextWithoutAnyJson() {
        assertThatThrownBy(() -> parser.parse("抱歉，我无法完成这个请求。", request))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("无法解析");
    }

    @Test
    void rejectsAPlanWithoutDaysAndSaysWhy() {
        assertThatThrownBy(() -> parser.parse("{\"title\": \"只有标题\", \"days\": []}", request))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("缺少 days");
    }

    @Test
    void errorMessageCarriesASnippetOfTheRawOutput() {
        assertThatThrownBy(() -> parser.parse("模型今天不想上班", request))
            .isInstanceOf(IllegalStateException.class)
            .hasMessageContaining("模型今天不想上班");
    }
}
