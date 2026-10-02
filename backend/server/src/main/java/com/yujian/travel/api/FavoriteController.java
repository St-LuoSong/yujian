package com.yujian.travel.api;

import com.yujian.travel.service.FavoriteService;
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

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/favorites")
public class FavoriteController {
    private final FavoriteService favoriteService;

    public FavoriteController(FavoriteService favoriteService) {
        this.favoriteService = favoriteService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public FavoriteModels.FavoriteResponse add(@Valid @RequestBody FavoriteModels.CreateRequest request) {
        return favoriteService.add(request);
    }

    @GetMapping
    public List<FavoriteModels.FavoriteResponse> list() {
        return favoriteService.list();
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void remove(@PathVariable UUID id) {
        favoriteService.remove(id);
    }

    @DeleteMapping("/poi/{poiId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void removeByPoiId(@PathVariable String poiId) {
        favoriteService.removeByPoiId(poiId);
    }
}
