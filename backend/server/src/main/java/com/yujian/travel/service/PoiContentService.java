package com.yujian.travel.service;

import com.yujian.travel.api.PoiModels;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.common.GeoCoordinate;
import com.yujian.travel.common.NearbySearch;
import com.yujian.travel.common.PoiImageAudit;
import com.yujian.travel.domain.PoiEntity;
import com.yujian.travel.domain.PoiMediaEntity;
import com.yujian.travel.repository.FavoriteRepository;
import com.yujian.travel.repository.PoiMediaRepository;
import com.yujian.travel.repository.PoiRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;

/**
 * 景点内容库的读写入口。
 *
 * 读路径有两个：游客端只看到 published=true 且顺序稳定的内容；管理台看到全部。
 * 写路径只对 ADMIN 开放（由 SecurityConfig 的 /api/admin/** 规则保证）。
 */
@Service
public class PoiContentService {
    private static final String DEFAULT_STATUS = "系统资料";
    private static final int MAX_LIMIT = 200;

    /** 首页一屏大约放得下 6 张卡片，作为分页默认值。 */
    private static final int DEFAULT_PAGE_SIZE = 6;
    /**
     * 单页上限。
     *
     * 允许客户端调大（"查看更多"页一次多拿几条），但不能让它传个 100000
     * 把整份目录一次拖走 —— 那正好是分页要解决的问题。
     */
    private static final int MAX_PAGE_SIZE = 50;

    /** 收藏榜的默认条数与上限：入口是"前十个"，但允许调用方翻更长的一份。 */
    private static final int DEFAULT_POPULAR_LIMIT = 10;
    private static final int MAX_POPULAR_LIMIT = 50;

    /**
     * 附近景点的半径与条数区间。
     *
     * 和分页一样：非法值夹回合法区间而不抛 400 —— "附近"是一个随手操作，
     * 不该因为滑杆传了个 0 就变成一张错误页。半径上限 20 公里，
     * 再大就不是"附近"了，该走城市筛选。
     */
    private static final int MIN_RADIUS_METERS = 200;
    private static final int MAX_RADIUS_METERS = 20000;
    private static final int DEFAULT_RADIUS_METERS = 3000;
    private static final int DEFAULT_NEARBY_LIMIT = 10;
    private static final int MAX_NEARBY_LIMIT = 50;

    private final PoiRepository repository;
    private final PoiMediaRepository mediaRepository;
    private final FavoriteRepository favoriteRepository;

    public PoiContentService(PoiRepository repository, PoiMediaRepository mediaRepository,
                             FavoriteRepository favoriteRepository) {
        this.repository = repository;
        this.mediaRepository = mediaRepository;
        this.favoriteRepository = favoriteRepository;
    }

    @Transactional(readOnly = true)
    public List<TravelModels.Poi> publicPois(String city) {
        List<PoiEntity> rows = city == null || city.isBlank()
            ? repository.findByPublishedTrueOrderBySortOrderAscNameAsc()
            : repository.findByPublishedTrueAndCityContainingOrderBySortOrderAscNameAsc(city.trim());
        return rows.stream().map(this::toPublic).toList();
    }

    @Transactional(readOnly = true)
    public Optional<TravelModels.Poi> publicPoi(String id) {
        return repository.findById(id)
            .filter(PoiEntity::isPublished)
            .map(this::toPublic);
    }

    /**
     * 上架景点的分页读取。
     *
     * 页码与页大小都容错：非法值一律夹回合法区间，不抛 400。首页只是想把内容
     * 铺出来，一个手滑的 page=0 不该变成一张错误页。
     */
    /**
     * 上架景点的分页读取（支持城市 / 分类 / 关键词）。
     *
     * 三个条件都在数据库里过滤。分类是精确匹配（分类是运营台维护的枚举式标签），
     * 城市与关键词是包含匹配 —— "洛阳"要能命中"洛阳"与"洛阳 · 伊川"这类写法。
     */
    @Transactional(readOnly = true)
    public TravelModels.PoiPage publicPoiPage(String city, String category, String keyword,
                                              Integer page, Integer size) {
        int safePage = page == null || page < 1 ? 1 : page;
        int safeSize = size == null || size < 1 ? DEFAULT_PAGE_SIZE : Math.min(size, MAX_PAGE_SIZE);
        Pageable pageable = PageRequest.of(safePage - 1, safeSize,
            Sort.by(Sort.Order.asc("sortOrder"), Sort.Order.asc("name")));
        Page<PoiEntity> rows = repository.searchPublished(
            trimToNull(city), trimToNull(category), trimToNull(keyword), pageable);
        List<TravelModels.Poi> items = rows.getContent().stream()
            .map(this::toPublic)
            .toList();
        return new TravelModels.PoiPage(items, safePage, safeSize, rows.getTotalElements(), rows.hasNext());
    }

    /** 首页"热门推荐"：运营台勾选的精选景点，最多 12 条。 */
    @Transactional(readOnly = true)
    public List<TravelModels.Poi> featuredPois() {
        return repository.findByPublishedTrueAndHomeFeaturedTrueOrderByFeaturedSortOrderAscSortOrderAscNameAsc()
            .stream()
            .limit(12)
            .map(this::toPublic)
            .toList();
    }

    /**
     * 收藏榜：按景点被收藏的次数排序，最多 {@code limit} 条。
     *
     * <p>收藏数为 0 的景点照样在榜上，只是排在后面：应用刚上线时没几个人收藏，
     * 空榜单对游客毫无用处，而"收藏少时按系统推荐补位"是一句能讲清楚的话。
     * 排序依次是：收藏数 → 运营精选 → 精选排序位 → 内容排序位 → 名称，
     * 因此同一份数据每次刷新顺序都一样，不会自己抖动。
     *
     * <p>聚合在数据库里做，排序在内存里做 —— 上架景点只有几十条，
     * 换来的是一条读得懂、测得动的排序规则。
     */
    @Transactional(readOnly = true)
    public List<TravelModels.PoiRank> popularPois(Integer limit) {
        int safeLimit = limit == null || limit < 1
            ? DEFAULT_POPULAR_LIMIT
            : Math.min(limit, MAX_POPULAR_LIMIT);

        Map<String, Long> counts = new HashMap<>();
        for (Object[] row : favoriteRepository.countGroupedByPoi()) {
            if (row.length >= 2 && row[0] instanceof String poiId && row[1] instanceof Long total) {
                counts.put(poiId, total);
            }
        }

        List<PoiEntity> ranked = new ArrayList<>(repository.findByPublishedTrueOrderBySortOrderAscNameAsc());
        ranked.sort(Comparator
            .comparingLong((PoiEntity poi) -> counts.getOrDefault(poi.getId(), 0L))
            .reversed()
            .thenComparing((PoiEntity poi) -> !poi.isHomeFeatured())
            .thenComparingInt(PoiEntity::getFeaturedSortOrder)
            .thenComparingInt(PoiEntity::getSortOrder)
            .thenComparing(PoiEntity::getName));

        return ranked.stream()
            .limit(safeLimit)
            .map(poi -> new TravelModels.PoiRank(toPublic(poi), counts.getOrDefault(poi.getId(), 0L)))
            .toList();
    }

    /**
     * 附近的景点。
     *
     * <p>入参 {@code lng} / {@code lat} 是设备定位的原始 <b>WGS-84</b> 坐标；
     * 内容库里的景点坐标是 <b>BD-09</b>，所以先换算再比距离（见 {@link GeoCoordinate}）。
     * 这一换算只在服务端做一次：坐标系是服务端的实现细节，
     * 不该让每一个已经发布出去的 APK 都各算一遍、各算错一遍。
     *
     * <p>只返回上架且**确实配了坐标**的景点。没配坐标的不参与计算，也不拿城市中心凑数 ——
     * 那种"看起来能用"的坐标比没有坐标更坏。跳过了多少个写在
     * {@link TravelModels.NearbyResult#skippedWithoutCoordinate()} 里，运营能看到。
     */
    @Transactional(readOnly = true)
    public TravelModels.NearbyResult nearbyPois(double lng, double lat, Integer radius, Integer limit) {
        int safeRadius = radius == null ? DEFAULT_RADIUS_METERS
            : Math.max(MIN_RADIUS_METERS, Math.min(MAX_RADIUS_METERS, radius));
        int safeLimit = limit == null ? DEFAULT_NEARBY_LIMIT
            : Math.max(1, Math.min(MAX_NEARBY_LIMIT, limit));

        List<PoiEntity> rows = repository.findByPublishedTrueOrderBySortOrderAscNameAsc();
        List<NearbySearch.Point> points = new ArrayList<>(rows.size());
        Map<String, PoiEntity> byId = new HashMap<>();
        int skipped = 0;
        for (PoiEntity row : rows) {
            if (row.getLng() == null || row.getLat() == null) {
                skipped++;
                continue;
            }
            points.add(new NearbySearch.Point(row.getId(), row.getLng(), row.getLat()));
            byId.put(row.getId(), row);
        }

        double[] center = GeoCoordinate.wgs84ToBd09(lng, lat);
        List<TravelModels.NearbyPoi> items = NearbySearch
            .rank(points, center[0], center[1], safeRadius, safeLimit).stream()
            .map(hit -> new TravelModels.NearbyPoi(toPublic(byId.get(hit.id())), hit.distanceMeters()))
            .toList();

        return new TravelModels.NearbyResult(items, safeRadius,
            "入参 WGS-84，服务端换算到 BD-09 后比较", skipped, DEFAULT_STATUS);
    }

    @Transactional(readOnly = true)
    public List<PoiModels.PoiView> adminList(String keyword) {
        List<PoiEntity> rows = repository.findAllByOrderBySortOrderAscNameAsc();
        if (keyword == null || keyword.isBlank()) {
            return rows.stream().map(this::toView).toList();
        }
        String needle = keyword.trim().toLowerCase(Locale.ROOT);
        return rows.stream()
            .filter(row -> contains(row.getName(), needle) || contains(row.getCity(), needle)
                || contains(row.getCategory(), needle))
            .map(this::toView)
            .toList();
    }

    @Transactional(readOnly = true)
    public PoiModels.PoiView adminGet(String id) {
        return toView(require(id));
    }

    @Transactional
    public PoiModels.PoiView create(PoiModels.PoiInput input) {
        PoiEntity entity = new PoiEntity();
        entity.setId(nextId());
        apply(entity, input);
        entity.setSortOrder(input.sortOrder() == null ? nextSortOrder() : input.sortOrder());
        entity.setPublished(!Boolean.FALSE.equals(input.published()));
        return toView(repository.save(entity));
    }

    @Transactional
    public PoiModels.PoiView update(String id, PoiModels.PoiInput input) {
        PoiEntity entity = require(id);
        apply(entity, input);
        if (input.sortOrder() != null) {
            entity.setSortOrder(input.sortOrder());
        }
        if (input.published() != null) {
            entity.setPublished(input.published());
        }
        // id 不变是刻意的：行程文本、收藏和分享链接都引用它。
        return toView(repository.save(entity));
    }

    @Transactional
    public PoiModels.PoiView setPublished(String id, boolean published) {
        PoiEntity entity = require(id);
        entity.setPublished(published);
        return toView(repository.save(entity));
    }

    @Transactional
    public void delete(String id) {
        PoiEntity entity = require(id);
        // 先清图集：poi_media 没有数据库级外键（列表页会整表读，外键只会让
        // 批量维护更别扭），所以删除景点时必须自己把子记录带走。
        mediaRepository.deleteByPoiId(id);
        repository.delete(entity);
    }

    /** 首页推荐位的开关与排序。 */
    @Transactional
    public PoiModels.PoiView setFeatured(String id, PoiModels.FeaturedInput input) {
        PoiEntity entity = require(id);
        if (input.homeFeatured() != null) {
            entity.setHomeFeatured(input.homeFeatured());
        }
        if (input.featuredSortOrder() != null) {
            entity.setFeaturedSortOrder(input.featuredSortOrder());
        }
        return toView(repository.save(entity));
    }

    // ---------- 景区图集 ----------

    @Transactional(readOnly = true)
    public List<PoiModels.MediaView> listMedia(String poiId) {
        require(poiId);
        return mediaViews(poiId);
    }

    @Transactional
    public PoiModels.MediaView addMedia(String poiId, PoiModels.MediaInput input) {
        require(poiId);
        PoiMediaEntity entity = new PoiMediaEntity();
        entity.setPoiId(poiId);
        applyMedia(entity, input);
        if (input.sortOrder() == null) {
            entity.setSortOrder(nextMediaSortOrder(poiId));
        }
        return toMediaView(mediaRepository.save(entity));
    }

    @Transactional
    public PoiModels.MediaView updateMedia(String poiId, Long mediaId, PoiModels.MediaInput input) {
        require(poiId);
        PoiMediaEntity entity = mediaRepository.findById(mediaId)
            .filter(row -> poiId.equals(row.getPoiId()))
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "POI_MEDIA_NOT_FOUND", "图片不存在"));
        applyMedia(entity, input);
        if (input.sortOrder() != null) {
            entity.setSortOrder(input.sortOrder());
        }
        return toMediaView(mediaRepository.save(entity));
    }

    @Transactional
    public void deleteMedia(String poiId, Long mediaId) {
        require(poiId);
        PoiMediaEntity entity = mediaRepository.findById(mediaId)
            .filter(row -> poiId.equals(row.getPoiId()))
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "POI_MEDIA_NOT_FOUND", "图片不存在"));
        mediaRepository.delete(entity);
    }

    @Transactional(readOnly = true)
    public long publishedCount() {
        return repository.countByPublishedTrue();
    }

    private PoiEntity require(String id) {
        if (id == null || id.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "POI_ID_REQUIRED", "缺少景点标识");
        }
        return repository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "POI_NOT_FOUND", "景点不存在"));
    }

    private void apply(PoiEntity entity, PoiModels.PoiInput input) {
        entity.setName(trim(input.name()));
        entity.setCity(trim(input.city()));
        entity.setCategory(trim(input.category()));
        entity.setImageUrl(trimToNull(input.imageUrl()));
        entity.setDescription(trim(input.description()));
        entity.setTicketFrom(input.ticketFrom() == null ? 0 : Math.max(0, input.ticketFrom()));
        entity.setDuration(trim(input.duration()));
        entity.setSuitability(trimToNull(input.suitability()));
        entity.setWeatherTip(trimToNull(input.weatherTip()));
        entity.setOpeningHours(trimToNull(input.openingHours()));
        entity.setReservationNote(trimToNull(input.reservationNote()));
        entity.setDataStatus(input.dataStatus() == null || input.dataStatus().isBlank()
            ? DEFAULT_STATUS : input.dataStatus().trim());
        entity.setImageCredit(trimToNull(input.imageCredit()));
        entity.setSourceUrl(trimToNull(input.sourceUrl()));
        entity.setLng(normalizeCoordinate(input.lng(), -180, 180));
        entity.setLat(normalizeCoordinate(input.lat(), -90, 90));
    }

    /**
     * 坐标校验：越界值一律当作"没填"，而不是抛错。
     *
     * 运营台的输入框可能被粘贴进奇怪的数字，拒绝写库比悄悄存一个错坐标安全，
     * 而地图对空坐标本就有降级路径（按名称解析）。
     */
    private static Double normalizeCoordinate(Double value, double min, double max) {
        if (value == null || value.isNaN() || value < min || value > max) {
            return null;
        }
        return value;
    }

    private int nextSortOrder() {
        return repository.findAllByOrderBySortOrderAscNameAsc().stream()
            .mapToInt(PoiEntity::getSortOrder)
            .max()
            .orElse(0) + 10;
    }

    private String nextId() {
        String base = "poi-" + Long.toHexString(System.nanoTime());
        String candidate = base;
        int suffix = 1;
        while (repository.existsById(candidate) && suffix < MAX_LIMIT) {
            candidate = base + "-" + suffix++;
        }
        return candidate;
    }

    private static boolean contains(String value, String needle) {
        return value != null && value.toLowerCase(Locale.ROOT).contains(needle);
    }

    private static String trim(String value) {
        return value == null ? "" : value.trim();
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private void applyMedia(PoiMediaEntity entity, PoiModels.MediaInput input) {
        entity.setImageUrl(trim(input.imageUrl()));
        entity.setCaption(trimToNull(input.caption()));
        entity.setImageCredit(trimToNull(input.imageCredit()));
        entity.setSourceUrl(trimToNull(input.sourceUrl()));
        entity.setPublished(!Boolean.FALSE.equals(input.published()));
    }

    private int nextMediaSortOrder(String poiId) {
        return mediaRepository.findByPoiIdOrderBySortOrderAscIdAsc(poiId).stream()
            .mapToInt(PoiMediaEntity::getSortOrder)
            .max()
            .orElse(0) + 10;
    }

    private static PoiModels.MediaView toMediaView(PoiMediaEntity entity) {
        return new PoiModels.MediaView(entity.getId(), entity.getPoiId(), entity.getImageUrl(),
            entity.getCaption(), entity.getImageCredit(), entity.getSourceUrl(),
            entity.getSortOrder(), entity.isPublished());
    }

    private List<PoiModels.MediaView> mediaViews(String poiId) {
        return mediaRepository.findByPoiIdOrderBySortOrderAscIdAsc(poiId).stream()
            .map(PoiContentService::toMediaView)
            .toList();
    }

    /** 详情页图集：只取上架的图，按运营排序。 */
    private List<String> galleryUrls(String poiId) {
        return mediaRepository.findByPoiIdAndPublishedTrueOrderBySortOrderAscIdAsc(poiId).stream()
            .map(PoiMediaEntity::getImageUrl)
            .filter(url -> url != null && !url.isBlank())
            .toList();
    }

    private TravelModels.Poi toPublic(PoiEntity entity) {
        return new TravelModels.Poi(entity.getId(), entity.getName(), entity.getCity(), entity.getCategory(),
            entity.getImageUrl(), entity.getDescription(), entity.getTicketFrom(), entity.getDuration(),
            entity.getSuitability(), entity.getWeatherTip(), entity.getDataStatus(),
            entity.getImageCredit(), entity.getSourceUrl(), verdictOf(entity).status(),
            entity.getOpeningHours(), entity.getReservationNote(), galleryUrls(entity.getId()));
    }

    private PoiModels.PoiView toView(PoiEntity entity) {
        PoiImageAudit.Verdict verdict = verdictOf(entity);
        return new PoiModels.PoiView(entity.getId(), entity.getName(), entity.getCity(), entity.getCategory(),
            entity.getImageUrl(), entity.getDescription(), entity.getTicketFrom(), entity.getDuration(),
            entity.getSuitability(), entity.getWeatherTip(), entity.getDataStatus(), entity.getImageCredit(),
            entity.getSourceUrl(), entity.getLng(), entity.getLat(), entity.isPublished(),
            entity.getSortOrder(), entity.getCreatedAt(), entity.getUpdatedAt(),
            verdict.status(), verdict.label(), verdict.gaps(),
            entity.getOpeningHours(), entity.getReservationNote(),
            entity.isHomeFeatured(), entity.getFeaturedSortOrder(),
            mediaViews(entity.getId()));
    }

    /**
     * 配图状态是派生的，不落库。
     *
     * 这样运营人员改完图片后不需要任何"重新审计"动作，下一次读就是新结论；
     * 也不会出现库里存着一个过期状态、界面照着它显示的情况。
     */
    private static PoiImageAudit.Verdict verdictOf(PoiEntity entity) {
        return PoiImageAudit.classify(entity.getImageUrl(), entity.getImageCredit(), entity.getSourceUrl());
    }
}
