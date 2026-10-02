package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityLikeEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface CommunityLikeRepository extends JpaRepository<CommunityLikeEntity, UUID> {
    boolean existsByUserIdAndPostId(UUID userId, UUID postId);

    Optional<CommunityLikeEntity> findByUserIdAndPostId(UUID userId, UUID postId);

    long countByPostId(UUID postId);
}
