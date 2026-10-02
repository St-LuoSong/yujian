package com.yujian.travel.service;

import com.yujian.travel.api.FavoriteModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.Favorite;
import com.yujian.travel.repository.FavoriteRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

@Service
public class FavoriteService {
    private final FavoriteRepository favoriteRepository;
    private final UserAccountRepository userRepository;

    public FavoriteService(FavoriteRepository favoriteRepository, UserAccountRepository userRepository) {
        this.favoriteRepository = favoriteRepository;
        this.userRepository = userRepository;
    }

    @Transactional
    public FavoriteModels.FavoriteResponse add(FavoriteModels.CreateRequest request) {
        AuthUser user = CurrentUser.requireUser();
        return favoriteRepository.findByUserIdAndPoiId(user.id(), request.poiId())
            .map(this::toResponse)
            .orElseGet(() -> {
                Favorite favorite = new Favorite();
                favorite.setUser(userRepository.getReferenceById(user.id()));
                favorite.setPoiId(request.poiId().trim());
                favorite.setPoiName(request.poiName().trim());
                favorite.setCity(request.city());
                favorite.setImageUrl(request.imageUrl());
                return toResponse(favoriteRepository.save(favorite));
            });
    }

    @Transactional(readOnly = true)
    public List<FavoriteModels.FavoriteResponse> list() {
        return favoriteRepository.findByUserIdOrderByCreatedAtDesc(CurrentUser.requireUser().id())
            .stream().map(this::toResponse).toList();
    }

    @Transactional
    public void remove(UUID id) {
        Favorite favorite = favoriteRepository.findByIdAndUserId(id, CurrentUser.requireUser().id())
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FAVORITE_NOT_FOUND", "收藏不存在或无权操作"));
        favoriteRepository.delete(favorite);
    }

    @Transactional
    public void removeByPoiId(String poiId) {
        Favorite favorite = favoriteRepository.findByUserIdAndPoiId(CurrentUser.requireUser().id(), poiId)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FAVORITE_NOT_FOUND", "收藏不存在或无权操作"));
        favoriteRepository.delete(favorite);
    }

    private FavoriteModels.FavoriteResponse toResponse(Favorite favorite) {
        return new FavoriteModels.FavoriteResponse(favorite.getId(), favorite.getPoiId(), favorite.getPoiName(),
            favorite.getCity(), favorite.getImageUrl(), favorite.getCreatedAt());
    }
}
