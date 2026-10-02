package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.tools.ToolCollection;
import com.yujian.travel.tools.ToolModels;
import com.yujian.travel.tools.ToolResult;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Component
public class TripPlanValidator {
    public ValidationReport validate(TravelModels.TripPlan plan, TravelModels.PlanRequest request,
                                     ToolCollection tools) {
        List<String> warnings = new ArrayList<>();
        for (int index = 0; index < plan.days().size(); index++) {
            TravelModels.TripDay day = plan.days().get(index);
            long attractionCount = day.items().stream().filter(item -> isAttraction(item.type())).count();
            if (attractionCount > 3) {
                warnings.add("第" + (index + 1) + "天安排了" + attractionCount + "个景点，建议减少或延长停留时间。");
            }
        }

        if (request.budgetPerPerson() != null && request.travelers() != null
            && request.budgetPerPerson() > 0 && plan.totalCost() > request.budgetPerPerson() * request.travelers()) {
            warnings.add("当前行程预算超过设定上限，可尝试替换餐饮或交通方案。");
        }
        RailFloor railFloor = lowestRailFare(tools);
        if (railFloor != null) {
            int travelers = request.travelers() == null || request.travelers() < 1 ? 2 : request.travelers();
            boolean roundTrip = plan.days().size() > 1;
            int required = railFloor.price() * travelers * (roundTrip ? 2 : 1);
            if (plan.totalCost() > 0 && plan.totalCost() < required) {
                warnings.add("12306 票价参考：" + railFloor.trainNo() + " " + railFloor.seatClass()
                    + "约 ¥" + railFloor.price() + "/人，" + travelers + "人"
                    + (roundTrip ? "往返" : "单程") + "合计约 ¥" + required
                    + "；当前方案总价 ¥" + plan.totalCost() + "，跨城交通预算可能不完整。");
            }
        }

        // 有可用天气值就检查，不因为这条数据是降级来源就跳过风险提示：
        // 宁可多提醒一次带伞，也不要漏掉一次降雨风险（降级来源已由工具轨迹单独标注）。
        //
        // 逐日检查而不是只看第一天：两天以上的行程里"第二天有雨"同样要提醒，
        // 提示语里带上城市与日期，用户才能核对这条风险说的是哪一天。
        for (Map.Entry<String, ToolResult<?>> entry : tools.results().entrySet()) {
            if (!entry.getKey().startsWith("getWeather")) {
                continue;
            }
            if (entry.getValue().data() instanceof ToolModels.WeatherInfo weather
                && weather.rainProbability() >= 50 && hasOutdoorActivity(plan)) {
                warnings.add(weather.city() + " " + weather.date() + " 降水概率 "
                    + weather.rainProbability() + "%，户外景点建议准备室内替代方案。");
                break;
            }
        }

        boolean hasRisk = plan.days().stream().flatMap(day -> day.items().stream())
            .anyMatch(item -> item.risk() != null && !item.risk().isBlank());
        if (hasRisk) {
            warnings.add("部分行程节点存在开放时间、天气或交通风险，请在出行前再次核验。");
        }

        return new ValidationReport(warnings, warnings.isEmpty(), intensityReason(plan));
    }

    private boolean hasOutdoorActivity(TravelModels.TripPlan plan) {
        return plan.days().stream().flatMap(day -> day.items().stream())
            .anyMatch(item -> {
                String title = item.title() == null ? "" : item.title();
                return title.contains("山") || title.contains("峡") || title.contains("峰")
                    || title.contains("石窟");
            });
    }

    /**
     * 找出当前工具数据里最低的铁路票价。
     *
     * 只把票价当作预算下限：不替用户选择席别，也不改写方案；如果方案总价低于
     * “最低票价 × 人数 × 往返”，就明确提示预算可能漏了跨城交通。
     */
    private RailFloor lowestRailFare(ToolCollection tools) {
        ToolResult<?> result = tools.results().get("quoteRailFares");
        if (result == null || !(result.data() instanceof List<?> list)) {
            return null;
        }
        RailFloor best = null;
        for (Object item : list) {
            if (!(item instanceof ToolModels.RailFare fare)) {
                continue;
            }
            for (Map.Entry<String, Integer> entry : fare.prices().entrySet()) {
                if (entry.getValue() == null || entry.getValue() <= 0) {
                    continue;
                }
                if (best == null || entry.getValue() < best.price()) {
                    best = new RailFloor(fare.trainNo(), entry.getKey(), entry.getValue());
                }
            }
        }
        return best;
    }

    private record RailFloor(String trainNo, String seatClass, int price) {
    }

    private String intensityReason(TravelModels.TripPlan plan) {
        long items = plan.days().stream().mapToLong(day -> day.items().size()).sum();
        long attractions = plan.days().stream().flatMap(day -> day.items().stream())
            .filter(item -> isAttraction(item.type())).count();
        return "共" + plan.days().size() + "天，" + attractions + "个景点，" + items + "个行程节点。";
    }

    /**
     * 判断一个节点是不是"景点"。
     *
     * 不能只认中文"景点"：模型经常按提示词里的英文枚举返回 attraction / museum，
     * 只比对中文会让"一天塞了 5 个景点"这条检查永远不触发，
     * 而它恰恰是行程强度判断最需要的一条约束。
     */
    private static boolean isAttraction(String type) {
        if (type == null || type.isBlank()) {
            return false;
        }
        String value = type.toLowerCase(Locale.ROOT);
        return value.contains("景点") || value.contains("门票") || value.contains("景区")
            || value.contains("博物馆") || value.contains("游览")
            || value.contains("attraction") || value.contains("sight")
            || value.contains("museum") || value.contains("tour");
    }
}
