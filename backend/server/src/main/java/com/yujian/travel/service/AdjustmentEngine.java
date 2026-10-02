package com.yujian.travel.service;

import com.yujian.travel.api.TravelModels;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class AdjustmentEngine {
    private AdjustmentEngine() {
    }

    public static Result adjust(TravelModels.TripPlan plan, String instruction) {
        String normalized = instruction == null ? "" : instruction.toLowerCase(Locale.ROOT);
        List<String> changes = new ArrayList<>();
        List<TravelModels.TripDay> days = new ArrayList<>(plan.days());

        if (containsAny(normalized, "轻松", "不要太累", "舒缓", "慢一点")) {
            days = lighten(days, changes);
        }
        if (containsAny(normalized, "美食", "餐", "小吃", "吃")) {
            days = addMeal(days, changes);
        }
        if (containsAny(normalized, "室内", "下雨", "雨天", "避雨")) {
            days = addIndoorAlternative(days, changes);
        }
        if (containsAny(normalized, "龙门")) {
            days = addSpecificAttraction(days, "龙门石窟", "景点", 90, "系统景点库", changes);
        }
        if (changes.isEmpty()) {
            changes.add("已根据你的描述重新平衡停留时长，并保留原有交通缓冲");
            days = lighten(days, new ArrayList<>());
        }

        int total = days.stream().flatMap(day -> day.items().stream()).mapToInt(TravelModels.TripItem::cost).sum();
        int travelers = Math.max(1, plan.perPersonCost() == 0 ? 1 : plan.totalCost() / plan.perPersonCost());
        TravelModels.TripPlan adjusted = new TravelModels.TripPlan(plan.id(), plan.title(),
            "已根据你的最新要求完成局部调整，建议出行前再次核对开放时间与交通信息。",
            plan.corridor(), inferIntensity(days), total, Math.max(1, total / travelers), days,
            mergeWarnings(plan.warnings()), plan.dataStatus());
        return new Result(adjusted, changes);
    }

    private static List<TravelModels.TripDay> lighten(List<TravelModels.TripDay> days, List<String> changes) {
        List<TravelModels.TripDay> result = new ArrayList<>();
        for (TravelModels.TripDay day : days) {
            List<TravelModels.TripItem> items = new ArrayList<>(day.items());
            if (items.size() > 2) {
                TravelModels.TripItem removed = items.remove(items.size() - 1);
                changes.add("移除“" + removed.title() + "”以降低当日行程强度");
            }
            result.add(new TravelModels.TripDay(day.label(), day.date(), items));
        }
        return result;
    }

    private static List<TravelModels.TripDay> addMeal(List<TravelModels.TripDay> days, List<String> changes) {
        if (days.isEmpty()) {
            return days;
        }
        List<TravelModels.TripDay> result = new ArrayList<>(days);
        TravelModels.TripDay first = result.get(0);
        List<TravelModels.TripItem> items = new ArrayList<>(first.items());
        boolean exists = items.stream().anyMatch(item -> "餐饮".equals(item.type()));
        if (!exists) {
            items.add(new TravelModels.TripItem("餐饮", "河南特色晚餐", "18:30", "约1.5小时",
                "步行 / 公共交通", "优先选择本地口碑餐馆，可根据预算调整",
                80, "系统推荐", "演示数据", "请确认营业时间与排队情况"));
            changes.add("增加河南特色晚餐节点");
        }
        result.set(0, new TravelModels.TripDay(first.label(), first.date(), items));
        return result;
    }

    private static List<TravelModels.TripDay> addIndoorAlternative(List<TravelModels.TripDay> days,
                                                                   List<String> changes) {
        List<TravelModels.TripDay> result = new ArrayList<>();
        for (TravelModels.TripDay day : days) {
            List<TravelModels.TripItem> items = new ArrayList<>();
            for (TravelModels.TripItem item : day.items()) {
                if (isOutdoor(item.title())) {
                    items.add(new TravelModels.TripItem("景点", "河南博物院", item.time(), "约2小时",
                        item.transport(), "雨天室内替代方案，重点展陈中原文明",
                        0, "系统景点库", "演示数据", "需提前确认预约名额"));
                    changes.add("将“" + item.title() + "”替换为室内备选方案");
                } else {
                    items.add(item);
                }
            }
            result.add(new TravelModels.TripDay(day.label(), day.date(), items));
        }
        return result;
    }

    private static List<TravelModels.TripDay> addSpecificAttraction(List<TravelModels.TripDay> days,
                                                                    String title, String type, int cost,
                                                                    String source, List<String> changes) {
        List<TravelModels.TripDay> result = new ArrayList<>(days);
        if (result.isEmpty()) {
            return result;
        }
        TravelModels.TripDay first = result.get(0);
        List<TravelModels.TripItem> items = new ArrayList<>(first.items());
        items.add(new TravelModels.TripItem(type, title, "14:00", "约2小时", "公共交通",
            "按你的要求加入行程，并预留景区间交通时间", cost, source, "演示数据", "请提前确认预约与开放时间"));
        changes.add("加入“" + title + "”并补充交通缓冲");
        result.set(0, new TravelModels.TripDay(first.label(), first.date(), items));
        return result;
    }

    private static boolean isOutdoor(String title) {
        return title.contains("山") || title.contains("峡") || title.contains("峰") || title.contains("石窟");
    }

    private static boolean containsAny(String text, String... keywords) {
        for (String keyword : keywords) {
            if (text.contains(keyword)) {
                return true;
            }
        }
        return false;
    }

    private static List<String> mergeWarnings(List<String> warnings) {
        List<String> result = new ArrayList<>(warnings);
        result.add("调整后请重新核对景点开放时间、交通与预算。");
        return result;
    }

    private static String inferIntensity(List<TravelModels.TripDay> days) {
        long itemCount = days.stream().mapToLong(day -> day.items().size()).sum();
        if (itemCount <= 3) {
            return "轻松";
        }
        return itemCount <= 6 ? "适中" : "紧凑";
    }

    public record Result(TravelModels.TripPlan plan, List<String> changes) {
    }
}
