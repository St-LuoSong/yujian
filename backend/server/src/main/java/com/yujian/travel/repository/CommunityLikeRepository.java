package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityLikeEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface CommunityLikeRepository extends JpaRepository<CommunityLikeEntity, UUID> {
    boolean existsByUserIdAndPostId(UUID userId, UUID postId);

    Optional<CommunityLikeEntity> findByUserIdAndPostId(UUID userId, UUID postId);

    long countByPostId(UUID postId);

    /**
     * 我的旅记收到的点赞。
     *
     * `liker.id <> :userId` 是"获得"这个词的全部含义：自己给自己点的不算。
     */
    @Query("select count(postLike) from CommunityLikeEntity postLike "
        + "where postLike.post.user.id = :userId and postLike.user.id <> :userId")
    long countReceivedByAuthor(@Param("userId") UUID userId);
}
