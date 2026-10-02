package com.yujian.travel.api;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 预览请求体的解析契约。
 *
 * 客户端"一句话规划"和"行程表单"共用这一个接口，服务端用它取出发日期，
 * 再去查天气、车次并给方案里的每一天打日期。字段名一旦对不上，
 * 用户选的那天就会被静默丢掉——正是"时间戳对不上"的成因。
 */
class TravelControllerPayloadTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void bindsTheDepartureDateTheClientSends() throws Exception {
        String body = """
            {"prompt":"两天洛阳","startDate":"2026-10-02","origin":"郑州",
             "destination":"洛阳","days":2,"travelers":2,
             "budgetPerPerson":1000,"interests":"历史文化","pace":"轻松","transport":"高铁"}
            """;

        TravelController.PlanRequestPayload payload =
            objectMapper.readValue(body, TravelController.PlanRequestPayload.class);

        assertThat(payload.startDate()).isEqualTo("2026-10-02");
        assertThat(payload.prompt()).isEqualTo("两天洛阳");
        assertThat(payload.days()).isEqualTo(2);
        assertThat(payload.transport()).isEqualTo("高铁");
    }

    @Test
    void leavesTheDateNullWhenTheClientOmitsIt() throws Exception {
        TravelController.PlanRequestPayload payload = objectMapper.readValue(
            "{\"prompt\":\"一句话\"}", TravelController.PlanRequestPayload.class);

        assertThat(payload.startDate()).isNull();
        assertThat(payload.origin()).isNull();
    }
}
