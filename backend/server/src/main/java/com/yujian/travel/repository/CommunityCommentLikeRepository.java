package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityCommentLikeEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface CommunityCommentLikeRepository
    extends JpaRepository<CommunityCommentLikeEntity, UUID> {

    boolean existsByUserIdAndCommentId(UUID userId, UUID commentId);

    Optional<CommunityCommentLikeEntity> findByUserIdAndCommentId(UUID userId, UUID commentId);

    /**
     * 我收到的评论点赞数。
     *
     * `liker.id <> :userId` 这一条是必须的：自己给自己的评论点赞不该算"获得"，
     * 否则"我获得的赞"就变成"我点过的赞"。旅记点赞与收藏走同样的口径。
     */
    @Query("select count(commentLike) from CommunityCommentLikeEntity commentLike "
        + "where commentLike.comment.user.id = :userId and commentLike.user.id <> :userId")
    long countReceivedByAuthor(@Param("userId") UUID userId);
}
