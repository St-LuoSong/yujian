package com.yujian.travel.repository;

import com.yujian.travel.domain.PoiEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PoiRepository extends JpaRepository<PoiEntity, String> {
    List<PoiEntity> findByPublishedTrueOrderBySortOrderAscNameAsc();

    List<PoiEntity> findByPublishedTrueAndCityContainingOrderBySortOrderAscNameAsc(String city);

    List<PoiEntity> findAllByOrderBySortOrderAscNameAsc();

    /**
     * 分页读上架景点。
     *
     * 方法名里不写 OrderBy：排序由调用方通过 Pageable 携带，
     * 这样"取第几页"和"怎么排"是两个互不干扰的参数。
     */
    Page<PoiEntity> findByPublishedTrue(Pageable pageable);

    Page<PoiEntity> findByPublishedTrueAndCityContaining(String city, Pageable pageable);

    long countByPublishedTrue();
}
