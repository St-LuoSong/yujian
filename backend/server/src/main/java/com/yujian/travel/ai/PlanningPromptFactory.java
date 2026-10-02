package com.yujian.travel.ai;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.PlanDates;
import com.yujian.travel.service.PromptVersionService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.time.LocalDate;

@Component
public class PlanningPromptFactory {
    private final ObjectMapper objectMapper;
    private final PromptVersionService promptVersionService;

    /** 测试用构造器：没有数据库时自动使用内置基线提示词。 */
    public PlanningPromptFactory(ObjectMapper objectMapper) {
        this(objectMapper, new PromptVersionService(null));
    }

    @Autowired
    public PlanningPromptFactory(ObjectMapper objectMapper, PromptVersionService promptVersionService) {
        this.objectMapper = objectMapper;
        this.promptVersionService = promptVersionService;
    }

    public String systemPrompt() {
        return promptVersionService.currentSystemPrompt();
    }

    /**
     * 用户侧提示词。
     *
     * 日期必须由服务端**写死给模型**，而不是让模型自己推断：
     * 真实故障里模型把出发日期猜成今天，于是方案标题写着 10-02 出发，
     * 风险提示却引用 10-01 的天气。这里把"今天 / 出发日 / 结束日"三件事
     * 明确写进提示词，并在返回的 days.date 上要求落在同一个区间内。
     */
    public String userPrompt(PlanningContext context) {
        TravelModels.PlanRequest request = context.request();
        LocalDate start = PlanDates.resolveStartDate(request.startDate());
        int days = PlanDates.resolveDays(request.days());
        String window = PlanDates.describe(start, days);
        try {
            return "今天（北京时间）：" + PlanDates.today().format(PlanDates.ISO)
                + "\n用户选定的出发日期：" + window + "，共 " + days + " 天。"
                + "\n用户需求：" + objectMapper.writeValueAsString(request)
                + "\n工具数据（键名带'第N天'的表示那一天的数据）："
                + objectMapper.writeValueAsString(context.tools().results())
                + "\n必须遵守："
                + "\n1. 只生成 " + days + " 天；days 里每一项的 date 必须依次落在 " + window
                + " 之内，禁止出现该区间以外的日期。"
                + "\n2. 天气、车次、票价只能引用工具数据里对应日期的条目；工具没有给出的日期，"
                + "不要编造当天的天气或车次。"
                + "\n3. duration 一律写成“约2小时30分钟”这样的中文，不允许出现小数。"
                + "\n4. cost 是整数元；没有依据就写 0，不要写“约120元”。"
                + "\n5. type 用中文：交通 / 景点 / 餐饮 / 住宿 / 活动。"
                + "\n6. 跨城交通只能使用 searchTrain、quoteRailFares、searchTransfer 的数据："
                + "直达有余票时优先直达；直达为空时才考虑中转。"
                + "\n7. 火车票价必须引用 quoteRailFares 并写明席别，禁止自行估算或把参考价写成官方实时价；"
                + "交通节点 cost 要把人数和往返一起算清楚，不能把票价漏在预算之外。"
                + "\n8. 明确标注演示数据风险。";
        } catch (Exception exception) {
            throw new IllegalStateException("无法构建规划提示词", exception);
        }
    }

    public String completePrompt(PlanningContext context) {
        return systemPrompt() + "\n\n" + userPrompt(context);
    }
}
