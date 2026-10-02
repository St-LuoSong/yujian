package com.yujian.travel.api;

import com.yujian.travel.service.TripPlanService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/trip-plans")
public class TripPlanController {
    private final TripPlanService tripPlanService;

    public TripPlanController(TripPlanService tripPlanService) {
        this.tripPlanService = tripPlanService;
    }

    @PostMapping
    public ResponseEntity<TravelModels.TripPlan> create(
        @Valid @RequestBody TripPlanModels.CreateRequest request,
        @RequestHeader(value = "X-Device-Fingerprint", required = false) String deviceFingerprint) {
        TripPlanModels.CreateResult result = tripPlanService.create(request, deviceFingerprint);
        ResponseEntity.BodyBuilder response = ResponseEntity.status(HttpStatus.CREATED);
        if (result.anonymousToken() != null) {
            response.header("X-Anonymous-Token", result.anonymousToken());
        }
        return response.body(result.plan());
    }

    @GetMapping
    public List<TripPlanModels.Summary> list() {
        return tripPlanService.list();
    }

    /**
     * "你的足迹"聚合。放在 {@code /{id}} 之前只是可读性上的顺序：
     * Spring 里字面量路径本来就优先于模板变量，{@code footprint} 不会被当成行程 id。
     * 这里写一句，免得后面有人"顺手"把顺序调回去还以为会出问题。
     */
    @GetMapping("/footprint")
    public TripPlanModels.Footprint footprint() {
        return tripPlanService.footprint();
    }

    @GetMapping("/{id}")
    public TravelModels.TripPlan get(@PathVariable UUID id) {
        return tripPlanService.get(id);
    }

    @PatchMapping("/{id}")
    public TravelModels.TripPlan patch(@PathVariable UUID id,
                                       @Valid @RequestBody TripPlanModels.PatchRequest request) {
        return tripPlanService.patch(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        tripPlanService.delete(id);
    }

    @PostMapping("/{id}/adjust")
    public TripPlanModels.AdjustmentResult adjust(@PathVariable UUID id,
                                                  @Valid @RequestBody TripPlanModels.AdjustRequest request) {
        return tripPlanService.adjust(id, request.instruction());
    }

    @PostMapping("/{id}/undo")
    public TravelModels.TripPlan undo(@PathVariable UUID id) {
        return tripPlanService.undo(id);
    }

    @GetMapping("/{id}/today")
    public TripPlanModels.TodayResponse today(@PathVariable UUID id) {
        return tripPlanService.today(id);
    }

    @GetMapping("/{id}/trace")
    public TripPlanModels.TraceResponse trace(@PathVariable UUID id) {
        return tripPlanService.trace(id);
    }
}
