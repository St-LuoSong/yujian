package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityCommentEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.UUID;
import java.util.Collection;
import java.util.List;

public interface CommunityCommentRepository extends JpaRepository<CommunityCommentEntity, UUID> {

    Page<CommunityCommentEntity> findByPostIdAndStatus(UUID postId, String status, Pageable pageable);

    /** 顶层评论分页。回复单独取，不参与分页 —— 它们跟着父评论一起出现。 */
    Page<CommunityCommentEntity> findByPostIdAndParentIdIsNullAndStatus(
        UUID postId, String status, Pageable pageable);

    /**
     * 这一页里所有顶层评论的回复，一次取完。
     *
     * 没有对单个父评论再做分页：一次最多 20 条顶层评论的回复量，在首版的量级下
     * 远比"每条父评论一次往返"划算。真出现单条几百回复时，这里应该换成
     * 按父评论分别截断的查询，而不是把整棵树拉回来。
     */
    List<CommunityCommentEntity> findByParentIdInAndStatusOrderByCreatedAtAsc(
        Collection<UUID> parentIds, String status);

    List<CommunityCommentEntity> findByParentIdInOrderByCreatedAtAsc(Collection<UUID> parentIds);

    List<CommunityCommentEntity> findByParentIdOrderByCreatedAtAsc(UUID parentId);

    long countByParentIdAndStatus(UUID parentId, String status);

    /** 运营端：一篇旅记下的顶层评论，不过滤状态。 */
    Page<CommunityCommentEntity> findByPostIdAndParentIdIsNull(UUID postId, Pageable pageable);

    /** 运营端视角：不过滤状态，隐藏的也要能看到，否则没法恢复。 */
    Page<CommunityCommentEntity> findByPostId(UUID postId, Pageable pageable);

    /** 我在旅记下发表过的、仍然可见的评论数。 */
    @Query("select count(comment) from CommunityCommentEntity comment "
        + "where comment.user.id = :userId and comment.status = :status")
    long countByAuthorAndStatus(@Param("userId") UUID userId, @Param("status") String status);

    /**
     * 旅记被删除时连带清掉它的评论。
     *
     * 用一条批量 delete 而不是先查出实体再逐条删：一篇热门旅记可能有几百条评论，
     * 逐条删会把这些行全部加载进持久化上下文，白白占内存。
     */
    // 只 flush 不 clear：调用方紧接着还要删除那条旅记实体，clear 会把托管态一起丢掉。
    @Modifying(flushAutomatically = true)
    @Query("delete from CommunityCommentEntity comment where comment.post.id = :postId")
    void deleteByPostId(@Param("postId") UUID postId);
}
