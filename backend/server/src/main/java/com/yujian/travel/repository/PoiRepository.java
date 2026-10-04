package com.yujian.travel.repository;

import com.yujian.travel.domain.PoiEntity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface PoiRepository extends JpaRepository<PoiEntity, String> {
    List<PoiEntity> findByPublishedTrueOrderBySortOrderAscNameAsc();

    List<PoiEntity> findByPublishedTrueAndCityContainingOrderBySortOrderAscNameAsc(String city);

    List<PoiEntity> findAllByOrderBySortOrderAscNameAsc();

    /** 首页精选：运营台勾选 home_featured 的景点，按运营排序。 */
    List<PoiEntity> findByPublishedTrueAndHomeFeaturedTrueOrderByFeaturedSortOrderAscSortOrderAscNameAsc();

    /**
     * 分页读上架景点。
     *
     * 方法名里不写 OrderBy：排序由调用方通过 Pageable 携带，
     * 这样"取第几页"和"怎么排"是两个互不干扰的参数。
     */
    Page<PoiEntity> findByPublishedTrue(Pageable pageable);

    Page<PoiEntity> findByPublishedTrueAndCityContaining(String city, Pageable pageable);

    /**
     * 内容库搜索。
     *
     * 关键词与分类都在 SQL 里过滤，而不是"先取一页再在内存里筛"：
     * 后者会让"搜索龙门"在第 2 页之后的结果里找不到任何东西，是最容易被
     * 当成"搜索坏了"的那类 bug。三个条件都可以为空，此时各自不生效。
     *
     * like 用 concat 拼通配符，避免把 % 写进参数再由 Hibernate 转义出错。
     */
    @Query("""
        select p from PoiEntity p
        where p.published = true
          and (:city is null or p.city like concat('%', :city, '%'))
          and (:category is null or p.category = :category)
          and (:keyword is null
               or p.name like concat('%', :keyword, '%')
               or p.city like concat('%', :keyword, '%')
               or p.category like concat('%', :keyword, '%')
               or p.description like concat('%', :keyword, '%'))
        """)
    Page<PoiEntity> searchPublished(@Param("city") String city,
                                    @Param("category") String category,
                                    @Param("keyword") String keyword,
                                    Pageable pageable);

    long countByPublishedTrue();
}
