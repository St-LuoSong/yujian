package com.yujian.travel.repository;

import com.yujian.travel.domain.UserMessageEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserMessageRepository extends JpaRepository<UserMessageEntity, UUID> {
    List<UserMessageEntity> findByUserIdOrderByCreatedAtDesc(UUID userId);

    List<UserMessageEntity> findByUserIdAndReadFalse(UUID userId);

    Optional<UserMessageEntity> findByIdAndUserId(UUID id, UUID userId);

    long countByUserIdAndReadFalse(UUID userId);

    boolean existsByUserId(UUID userId);
}
