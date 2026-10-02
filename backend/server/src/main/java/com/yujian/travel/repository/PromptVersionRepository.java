package com.yujian.travel.repository;

import com.yujian.travel.domain.PromptVersionEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PromptVersionRepository extends JpaRepository<PromptVersionEntity, UUID> {
    Optional<PromptVersionEntity> findFirstByActiveTrueOrderByCreatedAtDesc();

    List<PromptVersionEntity> findAllByOrderByCreatedAtDesc();

    List<PromptVersionEntity> findAllByActiveTrue();

    boolean existsByVersion(String version);
}
