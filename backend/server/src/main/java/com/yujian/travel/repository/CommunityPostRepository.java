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
}
