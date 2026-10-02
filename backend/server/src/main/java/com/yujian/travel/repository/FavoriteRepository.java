package com.yujian.travel.repository;

import com.yujian.travel.domain.Favorite;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FavoriteRepository extends JpaRepository<Favorite, UUID> {
    List<Favorite> findByUserIdOrderByCreatedAtDesc(UUID userId);

    Optional<Favorite> findByIdAndUserId(UUID id, UUID userId);

    boolean existsByUserIdAndPoiId(UUID userId, String poiId);

    Optional<Favorite> findByUserIdAndPoiId(UUID userId, String poiId);

    void deleteByUserId(UUID userId);
}
