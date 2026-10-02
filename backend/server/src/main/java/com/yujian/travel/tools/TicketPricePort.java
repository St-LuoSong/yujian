package com.yujian.travel.tools;

import com.yujian.travel.api.TravelModels;

import java.util.List;

/**
 * 门票价格端口。
 *
 * 和 {@link TravelToolPort} 一样，业务层只依赖这个接口：
 * 今天可以是景区内容库里的参考价，明天换成第三方比价服务，
 * 调用方与前端契约都不需要改，唯一变化的是 ToolResult 里的 source 与 dataStatus。
 */
public interface TicketPricePort {
    ToolResult<List<ToolModels.TicketPrice>> quote(List<TravelModels.Poi> pois, String city);
}

