package com.yujian.travel.tools;

import java.util.List;
import java.util.Map;

public final class ToolModels {
    private ToolModels() {
    }

    public record WeatherInfo(String city, String date, String condition, int minTemperature,
                              int maxTemperature, int rainProbability, String wind, String suggestion) {
    }

    public record RouteInfo(String origin, String destination, String mode, int durationMinutes,
                            int distanceMeters, String summary) {
    }

    /**
     * 一趟车的车次、时刻与席别余票。
     *
     * seats 是原始席别键到余票文案的映射（例如 second_class -> 有），
     * seatHint 是同一份数据的人类可读摘要。保留结构化席位是为了让票价校验
     * 能判断某个席别是否真的有票，而不是只看票价表。
     */
    public record TrainInfo(String trainNo, String from, String to, String departure, String arrival,
                            String duration, String seatHint, Map<String, String> seats) {
        public TrainInfo {
            seats = seats == null ? Map.of() : Map.copyOf(seats);
        }

        /** 兼容只关心车次摘要的旧调用方；没有席位数据时为空表，不伪造。 */
        public TrainInfo(String trainNo, String from, String to, String departure, String arrival,
                         String duration, String seatHint) {
            this(trainNo, from, to, departure, arrival, duration, seatHint, Map.of());
        }
    }

    /**
     * 12306 票价查询结果。
     *
     * prices 的键是中文席别（二等座、一等座、硬卧等），值是元。
     * 票价不塞进 TrainInfo：票价和余票来自两个工具、时效也不同，
     * 混成一条结果会让“车次查到了、票价没查到”这种真实情况失去来源与降级痕迹。
     */
    public record RailFare(String trainNo, String from, String to, String departure, String arrival,
                           String duration, String trainClass, Map<String, Integer> prices) {
        public RailFare {
            prices = prices == null ? Map.of() : Map.copyOf(prices);
        }
    }

    /** 12306 中转换乘的一段行程。 */
    public record RailTransferSegment(String trainNo, String from, String to, String departure,
                                      String arrival, String duration, Map<String, String> seats) {
        public RailTransferSegment {
            seats = seats == null ? Map.of() : Map.copyOf(seats);
        }
    }

    /**
     * 一次中转换乘方案。
     *
     * 只做一次换乘；不把中转站包装成“推荐购票组合”，购票仍由用户去官方渠道完成。
     */
    public record RailTransfer(String middleStation, String waitTime, String totalDuration,
                               List<RailTransferSegment> segments) {
        public RailTransfer {
            segments = segments == null ? List.of() : List.copyOf(segments);
        }
    }

    public record OpeningInfo(String poiName, String openingHours, boolean requiresReservation, String note) {
    }

    /**
     * 门票价格。
     *
     * provider 说明这个价是谁给的：内容库参考价、官方公示价还是第三方比价。
     * 价格是用户最敏感、也最容易过期的信息，所以必须带来源，不允许出现"裸价格"。
     */
    public record TicketPrice(String poiName, String city, int priceFrom, String provider, String note) {
    }
}
