package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;

import java.time.Instant;
import java.util.UUID;

public final class FavoriteModels {
    private FavoriteModels() {
    }

    public record CreateRequest(
        @NotBlank(message = "景点标识不能为空") String poiId,
        @NotBlank(message = "景点名称不能为空") String poiName,
        String city,
        String imageUrl) {
    }

    public record FavoriteResponse(UUID id, String poiId, String poiName, String city,
                                   String imageUrl, Instant createdAt) {
    }
}
