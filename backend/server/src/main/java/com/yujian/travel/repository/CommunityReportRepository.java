package com.yujian.travel.repository;

import com.yujian.travel.domain.CommunityReportEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface CommunityReportRepository extends JpaRepository<CommunityReportEntity, UUID> {
    boolean existsByReporterIdAndPostId(UUID reporterId, UUID postId);

    Page<CommunityReportEntity> findByStatusOrderByCreatedAtDesc(String status, Pageable pageable);
}
