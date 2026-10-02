package com.yujian.travel.tools;

import com.yujian.travel.api.TravelModels;

import java.util.List;

/**
 * 外部工具端口。
 *
 * 业务层只依赖这个接口，不关心背后是内容库、百度地图、开放天气接口还是本地演示数据。
 * 每个方法都必须如实返回 {@link ToolResult} 的状态：实时 / 缓存 / 系统资料 / 演示 / 降级。
 */
public interface TravelToolPort {
    ToolResult<List<TravelModels.Poi>> searchPoi(String keyword, String city);

    ToolResult<ToolModels.WeatherInfo> getWeather(String city, String date);

    ToolResult<ToolModels.RouteInfo> getRoute(String origin, String destination, String mode);

    ToolResult<List<ToolModels.TrainInfo>> searchTrain(String origin, String destination, String date);

    /**
     * 跨城铁路票价。
     *
     * 票价与余票分开查询，因此在接口层也分开返回：列车查到了但票价服务失败时，
     * 页面仍然能看到车次，预算校验则明确知道“这次没有票价依据”。
     */
    default ToolResult<List<ToolModels.RailFare>> quoteRailFares(String origin, String destination, String date) {
        return ToolResult.error("铁路票价", "RAIL_FARE_NOT_SUPPORTED", "当前工具实现不提供铁路票价");
    }

    /** 一次换乘方案；直达车次为空或用户明确需要中转时才展示。 */
    default ToolResult<List<ToolModels.RailTransfer>> searchTransfer(String origin, String destination, String date) {
        return ToolResult.error("铁路中转", "RAIL_TRANSFER_NOT_SUPPORTED", "当前工具实现不提供铁路中转查询");
    }

    ToolResult<List<ToolModels.OpeningInfo>> checkOpening(String destination);

    /**
     * 门票参考价 / 比价。
     *
     * 单独一个方法而不是塞进 searchPoi：价格属于"影响预算决策、且最容易过期"的数据，
     * 它需要自己的来源标注与降级原因，不能和景点介绍混在一条状态里。
     */
    ToolResult<List<ToolModels.TicketPrice>> quoteTicketPrices(List<TravelModels.Poi> pois, String city);
}
