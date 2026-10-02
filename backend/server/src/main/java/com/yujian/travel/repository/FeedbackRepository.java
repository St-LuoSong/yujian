package com.yujian.travel.repository;

import com.yujian.travel.domain.Feedback;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface FeedbackRepository extends JpaRepository<Feedback, UUID> {
    List<Feedback> findAllByOrderByCreatedAtDesc();

    List<Feedback> findByStatusOrderByCreatedAtDesc(String status);

    long countByStatus(String status);
}
