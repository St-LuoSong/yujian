package com.yujian.travel.repository;

import com.yujian.travel.domain.TripPlanEntity;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface TripPlanRepository extends JpaRepository<TripPlanEntity, UUID> {
    List<TripPlanEntity> findByOwnerIdOrderByUpdatedAtDesc(UUID ownerId);

    List<TripPlanEntity> findByAnonymousSessionIdOrderByUpdatedAtDesc(UUID anonymousSessionId);

    Optional<TripPlanEntity> findWithDetailsByIdAndOwnerId(UUID id, UUID ownerId);

    Optional<TripPlanEntity> findWithDetailsByIdAndAnonymousSessionId(UUID id, UUID anonymousSessionId);

    long countByOwnerIsNotNull();

    long countByAnonymousSessionIsNotNull();

    @Query("select avg(t.daysCount) from TripPlanEntity t")
    Double averageDaysCount();

    /** 近 N 天的创建时间。只取时间戳，避免把行程正文读进内存做统计。 */
    @Query("select t.createdAt from TripPlanEntity t where t.createdAt >= :from")
    List<Instant> findCreatedAtFrom(@Param("from") Instant from);
}
