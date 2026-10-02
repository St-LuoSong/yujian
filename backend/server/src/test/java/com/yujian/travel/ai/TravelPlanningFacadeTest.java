package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.PlanDates;
import com.yujian.travel.service.TripPlanFactory;
import com.yujian.travel.tools.MockTravelTools;
import com.yujian.travel.tools.ToolHealth;
import com.yujian.travel.tools.ToolModels;
import com.yujian.travel.tools.ToolOrchestrator;
import com.yujian.travel.tools.ToolResult;
import com.yujian.travel.tools.TravelToolPort;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The fallback chain is the whole point of the vendor layer, so it is verified
 * without touching a network: a failing vendor must hand over to the next one,
 * and a total failure must still produce a usable plan.
 */
class TravelPlanningFacadeTest {

    @Test
    void aFailingVendorHandsOverToTheNextOne() {
        ProviderHealth health = new ProviderHealth();
        TravelPlanningFacade facade = facadeWith(health,
            new StubEngine("openai", new IllegalStateException("401 Unauthorized")),
            new StubEngine("deepseek", null));

        PlanningOutcome outcome = facade.generate(request());

        assertThat(outcome.engine()).isEqualTo("deepseek");
        assertThat(outcome.fallback()).isFalse();
        assertThat(outcome.promptVersion()).isEqualTo(PromptDefaults.CURRENT_VERSION);
        assertThat(health.lastSuccessfulEngine()).isEqualTo("deepseek");
        assertThat(health.snapshots())
            .anySatisfy(snapshot -> {
                assertThat(snapshot.engine()).isEqualTo("openai");
                assertThat(snapshot.failureCount()).isEqualTo(1);
                assertThat(snapshot.lastError()).contains("401");
            });
    }

    @Test
    void everyVendorFailingFallsBackToTheMockEngine() {
        ProviderHealth health = new ProviderHealth();
        TravelPlanningFacade facade = facadeWith(health,
            new StubEngine("openai", new IllegalStateException("timeout")),
            new StubEngine("qwen", new IllegalStateException("502 Bad Gateway")));

        PlanningOutcome outcome = facade.generate(request());

        assertThat(outcome.engine()).isEqualTo("mock-fallback");
        assertThat(outcome.fallback()).isTrue();
        assertThat(outcome.plan().dataStatus()).isEqualTo("演示数据（AI 降级）");
        assertThat(outcome.plan().warnings())
            .anyMatch(warning -> warning.contains("AI 规划服务暂时不可用"));
        assertThat(health.lastSuccessfulEngine()).isNull();
    }

    @Test
    void aVendorThatIsNotConfiguredIsSkippedWithoutBeingCalled() {
        ProviderHealth health = new ProviderHealth();
        StubEngine unavailable = new StubEngine("kimi", null);
        unavailable.available = false;
        TravelPlanningFacade facade = facadeWith(health, unavailable);

        PlanningOutcome outcome = facade.generate(request());

        assertThat(unavailable.calls).isZero();
        assertThat(outcome.engine()).isEqualTo("mock-trip-factory");
        assertThat(outcome.fallback()).isFalse();
    }

    private static TravelPlanningFacade facadeWith(ProviderHealth health, PlanningEngine... engines) {
        return new TravelPlanningFacade(
            PlanningEngineRegistry.of(List.of(engines)),
            new MockPlanningEngine(new TripPlanFactory()),
            new TripPlanValidator(),
            new ToolOrchestrator(offlinePort(), null, new ToolHealth()),
            health);
    }

    /**
     * 离线端口替身：规划引擎的降级链与外部服务无关，测试里不能因为机器没网、
     * 或百度 AK 没配就变成不确定的结果，所以这里只保留确定性的演示数据。
     */
    private static TravelToolPort offlinePort() {
        MockTravelTools mock = new MockTravelTools();
        return new TravelToolPort() {
            @Override
            public ToolResult<List<TravelModels.Poi>> searchPoi(String keyword, String city) {
                return ToolResult.reference(List.of(), "测试景点库");
            }

            @Override
            public ToolResult<ToolModels.WeatherInfo> getWeather(String city, String date) {
                return mock.getWeather(city, date);
            }

            @Override
            public ToolResult<ToolModels.RouteInfo> getRoute(String origin, String destination, String mode) {
                return mock.getRoute(origin, destination, mode);
            }

            @Override
            public ToolResult<List<ToolModels.TrainInfo>> searchTrain(String origin, String destination, String date) {
                return mock.searchTrain(origin, destination, date);
            }

            @Override
            public ToolResult<List<ToolModels.OpeningInfo>> checkOpening(String destination) {
                return ToolResult.reference(List.of(), "测试景区资料");
            }

            @Override
            public ToolResult<List<ToolModels.TicketPrice>> quoteTicketPrices(List<TravelModels.Poi> pois,
                                                                              String city) {
                return ToolResult.reference(List.of(), "测试门票参考价");
            }
        };
    }

    private static TravelModels.PlanRequest request() {
        return new TravelModels.PlanRequest("两个人周末从郑州去洛阳", null, "郑州", "洛阳", 2, 2, 1000,
            "历史文化", "适中", "高铁");
    }

    /**
     * 出发日期必须由用户输入决定，而不是由模型或"今天"决定。
     *
     * 真实故障：客户端选了 10-02，服务端没有把日期传下去，模型自己猜成了 10-01，
     * 于是方案标题和风险提示里的日期对不上。这里锁住"每天 = 出发日 + 第 N 天"。
     */
    @Test
    void daysFollowTheTravellersStartDate() {
        ProviderHealth health = new ProviderHealth();
        TravelPlanningFacade facade = facadeWith(health, new StubEngine("deepseek", null));

        LocalDate start = PlanDates.today().plusDays(30);
        TravelModels.PlanRequest dated = new TravelModels.PlanRequest("两天洛阳",
            start.format(PlanDates.ISO), "郑州", "洛阳", 2, 2, 1000, "历史文化", "适中", "高铁");

        PlanningOutcome outcome = facade.generate(dated);

        assertThat(outcome.plan().days()).hasSize(2);
        assertThat(outcome.plan().days().get(0).date()).isEqualTo(start.format(PlanDates.ISO));
        assertThat(outcome.plan().days().get(1).date())
            .isEqualTo(start.plusDays(1).format(PlanDates.ISO));
    }

    /** Engine double: either answers with the bundled plan or throws. */
    private static final class StubEngine implements PlanningEngine {
        private final String name;
        private final RuntimeException failure;
        private final TripPlanFactory factory = new TripPlanFactory();
        private boolean available = true;
        private int calls;

        private StubEngine(String name, RuntimeException failure) {
            this.name = name;
            this.failure = failure;
        }

        @Override
        public String name() {
            return name;
        }

        @Override
        public boolean available() {
            return available;
        }

        @Override
        public TravelModels.TripPlan generate(PlanningContext context) {
            calls++;
            if (failure != null) {
                throw failure;
            }
            return factory.create(context.request());
        }
    }
}
