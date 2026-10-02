package com.yujian.travel.infrastructure.external.railway;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.tools.ToolModels;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class RailwayMcpClientParsingTest {
    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    void trainsCarryStructuredSeatAvailability() throws Exception {
        JsonNode payload = objectMapper.readTree("""
            {"success":true,"trains":[
              {"train_no":"G1903","from_station":"郑州东","to_station":"洛阳龙门",
               "start_time":"08:20","arrive_time":"08:56","duration":"00:36",
               "seats":{"business":"3","first_class":"有","second_class":"有","no_seat":"-"}}
            ]}
            """);

        List<ToolModels.TrainInfo> trains = RailwayMcpClient.trainsFrom(payload, "2026-10-03");

        assertThat(trains).hasSize(1);
        assertThat(trains.get(0).trainNo()).isEqualTo("G1903");
        assertThat(trains.get(0).seats())
            .containsEntry("business", "3")
            .containsEntry("first_class", "有")
            .doesNotContainKey("no_seat");
        assertThat(trains.get(0).seatHint()).contains("二等座 有票");
    }

    @Test
    void faresDropInvalidPricesAndKeepSeatNames() throws Exception {
        JsonNode payload = objectMapper.readTree("""
            {"success":true,"data":[
              {"train_no":"240000G19030","train_code":"G1903","from_station":"郑州东",
               "to_station":"洛阳龙门","start_time":"08:20","arrive_time":"08:56",
               "duration":"00:36","train_class_name":"高铁",
               "prices":{"二等座":"65.5","一等座":"104","无座":"--"}}
            ]}
            """);

        List<ToolModels.RailFare> fares = RailwayMcpClient.faresFrom(payload);

        assertThat(fares).hasSize(1);
        assertThat(fares.get(0).trainNo()).isEqualTo("G1903");
        assertThat(fares.get(0).prices())
            .containsEntry("二等座", 66)
            .containsEntry("一等座", 104)
            .doesNotContainKey("无座");
    }

    @Test
    void transfersKeepBothSegmentsAndSeats() throws Exception {
        JsonNode payload = objectMapper.readTree("""
            {"success":true,"transfers":[
              {"middle_station":"郑州东","wait_time":"约35分钟","total_duration":"02:10",
               "segments":[
                 {"train_code":"G1001","from_station":"安阳东","to_station":"郑州东",
                  "start_time":"08:00","arrive_time":"08:40","duration":"00:40",
                  "seats":{"二等座":"有"}},
                 {"train_code":"G2001","from_station":"郑州东","to_station":"洛阳龙门",
                  "start_time":"09:15","arrive_time":"10:10","duration":"00:55",
                  "seats":{"二等座":"3"}}
               ]}
            ]}
            """);

        List<ToolModels.RailTransfer> transfers = RailwayMcpClient.transfersFrom(payload);

        assertThat(transfers).hasSize(1);
        assertThat(transfers.get(0).middleStation()).isEqualTo("郑州东");
        assertThat(transfers.get(0).segments()).hasSize(2);
        assertThat(transfers.get(0).segments().get(1).seats()).containsEntry("二等座", "3");
    }

    @Test
    void priceParserRoundsYuanAndRejectsUnusableValues() {
        assertThat(RailwayMcpClient.priceYuan("55.5")).isEqualTo(56);
        assertThat(RailwayMcpClient.priceYuan("65")).isEqualTo(65);
        assertThat(RailwayMcpClient.priceYuan("--")).isNull();
        assertThat(RailwayMcpClient.priceYuan("not-a-price")).isNull();
    }
}
