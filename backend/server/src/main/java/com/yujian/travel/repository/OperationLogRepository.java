package com.yujian.travel.repository;

import com.yujian.travel.domain.OperationLog;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface OperationLogRepository extends JpaRepository<OperationLog, UUID> {
    List<OperationLog> findAllByOrderByCreatedAtDesc(Pageable pageable);
}
