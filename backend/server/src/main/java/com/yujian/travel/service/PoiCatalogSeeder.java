package com.yujian.travel.service;

import com.yujian.travel.api.TravelCatalog;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.domain.PoiEntity;
import com.yujian.travel.repository.PoiRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 首次启动时把内置的三条示范走廊景点写进内容库。
 *
 * 只在表为空时插入，因此管理台之后的增删改不会被重启覆盖。
 * 图片仍旧是占位素材，交付前必须在管理台逐条替换为有授权的河南实拍图。
 *
 * 坐标是另一回事：地图要能打点，就必须有坐标。这里给四个示范景点预置了
 * 百度地理编码解析出来的值（BD09），并在每次启动时**只补空值**，
 * 这样已经跑起来的开发库也能自动获得坐标，而运营台手工改过的值不会被覆盖。
 */
@Component
public class PoiCatalogSeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(PoiCatalogSeeder.class);
    private static final String PLACEHOLDER_CREDIT = "Unsplash 示例素材，交付前需替换为河南实拍授权图";

    /**
     * 示范景点的初始坐标（百度坐标系 BD09）。
     *
     * 由百度地图地理编码解析得到，运营台可以随时改成实测值；
     * 使用 LinkedHashMap 而不是 Map.of 是为了让写入顺序稳定，便于对照日志。
     */
    private static final Map<String, double[]> SEED_COORDINATES = seedCoordinates();

    private static Map<String, double[]> seedCoordinates() {
        Map<String, double[]> values = new LinkedHashMap<>();
        values.put("longmen", new double[] {112.484008, 34.564649});
        values.put("shaolin", new double[] {112.947812, 34.513201});
        values.put("yuntai", new double[] {113.382019, 35.461608});
        values.put("qingming", new double[] {114.346893, 34.814934});
        return Map.copyOf(values);
    }

    private final PoiRepository repository;

    public PoiCatalogSeeder(PoiRepository repository) {
        this.repository = repository;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (repository.count() == 0) {
            seedCatalog();
        }
        int repaired = backfillCoordinates();
        if (repaired > 0) {
            log.info("Backfilled coordinates for {} seeded POI rows", repaired);
        }
    }

    private void seedCatalog() {
        int sortOrder = 10;
        for (TravelModels.Poi poi : TravelCatalog.pois()) {
            PoiEntity entity = new PoiEntity();
            entity.setId(poi.id());
            entity.setName(poi.name());
            entity.setCity(poi.city());
            entity.setCategory(poi.category());
            entity.setImageUrl(poi.imageUrl());
            entity.setDescription(poi.description());
            entity.setTicketFrom(poi.ticketFrom());
            entity.setDuration(poi.duration());
            entity.setSuitability(poi.suitability());
            entity.setWeatherTip(poi.weatherTip());
            entity.setDataStatus(poi.dataStatus() == null ? "系统资料" : poi.dataStatus());
            entity.setImageCredit(PLACEHOLDER_CREDIT);
            entity.setPublished(true);
            entity.setSortOrder(sortOrder);
            sortOrder += 10;
            applySeedCoordinate(entity);
            repository.save(entity);
        }
        log.info("Seeded {} POI rows into the content library", repository.count());
    }

    /**
     * 补齐缺失坐标。
     *
     * 只动 lng 或 lat 为空的示范景点：运营台填过的值一律保留，
     * 因此这个方法在每次启动时运行也不会覆盖人工数据。
     */
    private int backfillCoordinates() {
        List<PoiEntity> rows = repository.findAll();
        int repaired = 0;
        for (PoiEntity entity : rows) {
            if (entity.getLng() != null && entity.getLat() != null) {
                continue;
            }
            if (!SEED_COORDINATES.containsKey(entity.getId())) {
                continue;
            }
            applySeedCoordinate(entity);
            repository.save(entity);
            repaired++;
        }
        return repaired;
    }

    private static void applySeedCoordinate(PoiEntity entity) {
        double[] coordinate = Optional.ofNullable(SEED_COORDINATES.get(entity.getId())).orElse(null);
        if (coordinate == null) {
            return;
        }
        entity.setLng(coordinate[0]);
        entity.setLat(coordinate[1]);
    }
}
