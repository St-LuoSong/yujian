package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityPostEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface CommunityPostRepository extends JpaRepository<CommunityPostEntity, UUID> {
    @EntityGraph(attributePaths = {"user", "tripPlan"})
    Page<CommunityPostEntity> findByStatusAndVisibilityOrderByPublishedAtDescCreatedAtDesc(
        String status, String visibility, Pageable pageable);

    @EntityGraph(attributePaths = {"user", "tripPlan"})
    Page<CommunityPostEntity> findByStatusAndVisibilityAndCityIgnoreCaseOrderByPublishedAtDescCreatedAtDesc(
        String status, String visibility, String city, Pageable pageable);

    @EntityGraph(attributePaths = {"user", "tripPlan"})
    Page<CommunityPostEntity> findByStatusAndVisibilityAndTagsContainingIgnoreCaseOrderByPublishedAtDescCreatedAtDesc(
        String status, String visibility, String tag, Pageable pageable);

    @EntityGraph(attributePaths = {"user", "tripPlan"})
    Page<CommunityPostEntity> findByUserIdOrderByCreatedAtDesc(UUID userId, Pageable pageable);

    @EntityGraph(attributePaths = {"user", "tripPlan"})
    Page<CommunityPostEntity> findByStatusOrderByCreatedAtAsc(String status, Pageable pageable);

    @Query("select p from CommunityPostEntity p join fetch p.user left join fetch p.tripPlan where p.id = :id")
    Optional<CommunityPostEntity> findWithDetailsById(@Param("id") UUID id);

    long countByStatus(String status);

    /**
     * 还有多少篇其它旅记引用这张图片。
     *
     * 按文件名做宽松匹配：同一张图在不同记录里可能存成 `/media/x.jpg` 或
     * `http://host/media/x.jpg` 两种写法，只比文件名才不会漏判。
     */
    @Query("select count(p) from CommunityPostEntity p join p.imageUrls i "
        + "where i like concat('%', :fileName, '%') and p.id <> :excludeId")
    long countOthersUsingImageFile(@Param("fileName") String fileName,
                                   @Param("excludeId") UUID excludeId);
}
