package com.yujian.travel.repository;

import com.yujian.travel.domain.Favorite;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FavoriteRepository extends JpaRepository<Favorite, UUID> {
    List<Favorite> findByUserIdOrderByCreatedAtDesc(UUID userId);

    Optional<Favorite> findByIdAndUserId(UUID id, UUID userId);

    boolean existsByUserIdAndPoiId(UUID userId, String poiId);

    Optional<Favorite> findByUserIdAndPoiId(UUID userId, String poiId);

    void deleteByUserId(UUID userId);

    /**
     * 每个景点被收藏的次数，形如 {@code [poiId, count]}。
     *
     * 只做聚合，不在 SQL 里排序或取前 N：内容库只有几十条，排序规则
     * （收藏数 → 运营精选 → 运营排序位 → 名称）放在服务层比写进一条原生
     * SQL 更好读，也更好测。目录涨到几千条时再把它换成 join + limit。
     */
    @Query("select f.poiId, count(f) from Favorite f group by f.poiId")
    List<Object[]> countGroupedByPoi();
}
