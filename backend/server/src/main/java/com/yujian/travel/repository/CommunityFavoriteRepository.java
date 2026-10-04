package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityFavoriteEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface CommunityFavoriteRepository extends JpaRepository<CommunityFavoriteEntity, UUID> {
    boolean existsByUserIdAndPostId(UUID userId, UUID postId);

    Optional<CommunityFavoriteEntity> findByUserIdAndPostId(UUID userId, UUID postId);

    long countByPostId(UUID postId);

    /** 我的旅记被收藏的次数；自己收藏自己的不算"获得"。 */
    @Query("select count(favorite) from CommunityFavoriteEntity favorite "
        + "where favorite.post.user.id = :userId and favorite.user.id <> :userId")
    long countReceivedByAuthor(@Param("userId") UUID userId);

    /** 我的收藏列表：按收藏时间倒序，带上作者与关联行程。 */
    @EntityGraph(attributePaths = {"post", "post.user", "post.tripPlan"})
    Page<CommunityFavoriteEntity> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable pageable);
}
