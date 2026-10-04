package com.yujian.travel.repository;

import com.yujian.travel.domain.ThemeRouteEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ThemeRouteRepository extends JpaRepository<ThemeRouteEntity, String> {
    List<ThemeRouteEntity> findByPublishedTrueOrderBySortOrderAscIdAsc();

    List<ThemeRouteEntity> findAllByOrderBySortOrderAscIdAsc();
}
