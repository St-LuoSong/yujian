package com.yujian.travel.repository;

import com.yujian.travel.domain.PoiMediaEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PoiMediaRepository extends JpaRepository<PoiMediaEntity, Long> {
    List<PoiMediaEntity> findByPoiIdAndPublishedTrueOrderBySortOrderAscIdAsc(String poiId);

    List<PoiMediaEntity> findByPoiIdOrderBySortOrderAscIdAsc(String poiId);

    void deleteByPoiId(String poiId);
}
