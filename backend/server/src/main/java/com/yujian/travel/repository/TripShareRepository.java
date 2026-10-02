package com.yujian.travel.repository;

import com.yujian.travel.domain.TripShare;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface TripShareRepository extends JpaRepository<TripShare, UUID> {
    Optional<TripShare> findByTokenHashAndEnabledTrue(String tokenHash);

    Optional<TripShare> findByIdAndTripPlanOwnerId(UUID id, UUID ownerId);

    long countByEnabledTrueAndExpiresAtAfter(Instant now);

    @Query("select coalesce(sum(s.viewCount), 0) from TripShare s")
    long totalViewCount();

    @Modifying
    @Query("delete from TripShare s where s.tripPlan.owner.id = :ownerId")
    void deleteByTripPlanOwnerId(@Param("ownerId") UUID ownerId);
}
