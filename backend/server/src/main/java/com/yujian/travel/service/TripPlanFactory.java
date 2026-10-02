package com.yujian.travel.service;

import com.yujian.travel.api.TravelModels;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class TripPlanFactory {
    public TravelModels.TripPlan create(TravelModels.PlanRequest request) {
        String destination = inferDestination(request);
        boolean kaifeng = destination.contains("开封");
        boolean yuntai = destination.contains("云台");
        String corridor = kaifeng ? "郑州—开封" : yuntai ? "焦作—云台山" : "郑州—洛阳";
        String title = kaifeng ? "开封宋韵一日游" : yuntai ? "云台山周末轻旅行" : "洛阳历史文化两日游";
        List<TravelModels.TripDay> days = kaifeng ? kaifengPlan() : yuntai ? yuntaiPlan() : luoyangPlan();
        int requestedDays = request.days() == null ? days.size() : Math.max(1, Math.min(request.days(), days.size()));
        days = new ArrayList<>(days.subList(0, requestedDays));
        int total = days.stream().flatMap(day -> day.items().stream()).mapToInt(TravelModels.TripItem::cost).sum();
        int travelers = request.travelers() == null || request.travelers() < 1 ? 2 : request.travelers();
        return new TravelModels.TripPlan(UUID.randomUUID().toString(), title,
            "基于景点时长、路线衔接、开放时间和天气提示整理的可执行方案。", corridor,
            inferIntensity(days), total, Math.max(1, total / travelers), days,
            List.of("门票、开放时间和交通信息请以官方渠道为准。",
                "行程时间与顺序为系统整理的参考编排，各项数据的实时性以「依据」页的标注为准。"), "演示数据");
    }

    private String inferDestination(TravelModels.PlanRequest request) {
        if (request.destination() != null && !request.destination().isBlank()) {
            return request.destination();
        }
        String prompt = request.prompt() == null ? "" : request.prompt();
        if (prompt.contains("开封")) {
            return "开封";
        }
        if (prompt.contains("云台")) {
            return "云台山";
        }
        return "洛阳";
    }

    private String inferIntensity(List<TravelModels.TripDay> days) {
        long itemCount = days.stream().mapToLong(day -> day.items().size()).sum();
        if (itemCount <= 3) {
            return "轻松";
        }
        return itemCount <= 6 ? "适中" : "紧凑";
    }

    private List<TravelModels.TripDay> luoyangPlan() {
        return List.of(
            new TravelModels.TripDay("DAY 01", "古都与石窟", List.of(
                item("09:00", "龙门石窟", "景点", "高铁站至景区约45分钟", 90, "百度地图/景区资料", "建议提前预约，上午光线更适合游览"),
                item("14:00", "洛阳博物馆", "景点", "从龙门石窟前往约30分钟", 0, "系统景点库", "周一通常闭馆，请以官方公告为准"),
                item("18:30", "洛阳水席", "餐饮", "建议预留90分钟", 80, "系统推荐", "可根据口味调整餐厅"))),
            new TravelModels.TripDay("DAY 02", "古寺与城市", List.of(
                item("09:00", "白马寺", "景点", "建议游览2小时", 35, "系统景点库", "节假日客流较大"),
                item("13:30", "隋唐洛阳城", "景点", "城市漫游与夜景", 60, "系统景点库", "夜游时段以景区公告为准"),
                item("17:30", "返程", "交通", "预留换乘缓冲时间", 120, "交通估算", "返程车次需单独确认"))));
    }

    private List<TravelModels.TripDay> kaifengPlan() {
        return List.of(new TravelModels.TripDay("DAY 01", "宋韵一日", List.of(
            item("09:30", "开封府", "景点", "郑州东至开封约35分钟", 65, "系统景点库", "建议提前查看开衙仪式时间"),
            item("13:30", "清明上河园", "景点", "建议下午入园并预留夜游", 120, "景区资料", "演出时间会随季节调整"),
            item("19:00", "鼓楼夜市", "餐饮", "本地特色小吃探索", 70, "系统推荐", "夜间注意返程交通时间"))));
    }

    private List<TravelModels.TripDay> yuntaiPlan() {
        return List.of(
            new TravelModels.TripDay("DAY 01", "红石峡与潭瀑峡", List.of(
                item("08:30", "红石峡", "景点", "建议穿舒适防滑鞋", 120, "景区资料", "雨天路滑，需关注景区开放信息"),
                item("14:00", "潭瀑峡", "景点", "根据天气情况调整", 0, "系统景点库", "强降雨天气可能临时关闭"),
                item("18:00", "云台山周边", "住宿", "建议提前确认房态", 180, "系统推荐", "节假日住宿价格波动较大"))),
            new TravelModels.TripDay("DAY 02", "山顶风物", List.of(
                item("09:00", "茱萸峰", "景点", "户外活动受天气影响", 60, "景区资料", "山路较多，体力要求较高"),
                item("15:00", "返程", "交通", "预留山路和换乘时间", 100, "交通估算", "山区交通耗时可能增加"))));
    }

    private TravelModels.TripItem item(String time, String title, String type, String description,
                                       int cost, String source, String risk) {
        return new TravelModels.TripItem(type, title, time, "约2小时", "公共交通 / 步行",
            description, cost, source, "演示数据", risk);
    }
}
