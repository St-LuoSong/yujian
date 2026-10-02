package com.yujian.travel.api;

import com.yujian.travel.service.TripShareService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api")
public class TripShareController {
    private final TripShareService tripShareService;

    public TripShareController(TripShareService tripShareService) {
        this.tripShareService = tripShareService;
    }

    @PostMapping("/trip-plans/{id}/share")
    public TripPlanModels.ShareResult create(@PathVariable UUID id,
                                             @Valid @RequestBody(required = false)
                                             TripPlanModels.ShareRequest request) {
        return tripShareService.create(id, request);
    }

    @GetMapping("/trip-shares/{token}")
    public TripPlanModels.SharedTrip view(@PathVariable String token) {
        return tripShareService.view(token);
    }

    @DeleteMapping("/trip-shares/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void revoke(@PathVariable UUID id) {
        tripShareService.revoke(id);
    }
}
