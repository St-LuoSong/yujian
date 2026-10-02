package com.yujian.travel.repository;

import com.yujian.travel.domain.DemoScenarioEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface DemoScenarioRepository extends JpaRepository<DemoScenarioEntity, UUID> {
    List<DemoScenarioEntity> findAllByOrderByScenarioKeyAscMatchKeyAsc();

    Optional<DemoScenarioEntity> findByScenarioKeyAndMatchKey(String scenarioKey, String matchKey);

    Optional<DemoScenarioEntity> findByScenarioKeyAndMatchKeyAndEnabledTrue(String scenarioKey, String matchKey);
}
