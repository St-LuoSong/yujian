package com.yujian.travel.service;

import com.yujian.travel.api.ContentModels;
import com.yujian.travel.api.TravelCatalog;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.AppVisualResourceEntity;
import com.yujian.travel.domain.CultureArticleEntity;
import com.yujian.travel.domain.ThemeRouteEntity;
import com.yujian.travel.repository.AppVisualResourceRepository;
import com.yujian.travel.repository.CultureArticleRepository;
import com.yujian.travel.repository.ThemeRouteRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

/**
 * 平台内容库：应用视觉资源、主题路线、文化锦囊。
 *
 * 三类内容有一个共同点 —— 它们都由运营台维护、对游客只读、并且**允许为空**。
 * 为空时客户端退回内置占位或空状态，而不是显示一条编造的内容。
 */
@Service
public class ContentLibraryService {
    /**
     * 允许的视觉资源槽。
     *
     * 白名单而不是"随便什么 key 都能存"：客户端只认这几个槽，写进一个
     * 拼错的槽名，只会在某天发现"配了图但首页没变"。
     */
    public static final List<String> VISUAL_SLOTS = List.of(
        "HOME_HERO",
        "PROFILE_HEADER",
        "TRIP_DEFAULT_COVER",
        "ATTRACTION_PLACEHOLDER",
        "COMMUNITY_PLACEHOLDER",
        "CULTURE_HEADER"
    );

    private static final int CULTURE_PREVIEW_LIMIT = 4;

    private final AppVisualResourceRepository visualRepository;
    private final ThemeRouteRepository routeRepository;
    private final CultureArticleRepository articleRepository;

    public ContentLibraryService(AppVisualResourceRepository visualRepository,
                                 ThemeRouteRepository routeRepository,
                                 CultureArticleRepository articleRepository) {
        this.visualRepository = visualRepository;
        this.routeRepository = routeRepository;
        this.articleRepository = articleRepository;
    }

    // ---------- 游客端读 ----------

    @Transactional(readOnly = true)
    public List<TravelModels.ThemeRoute> publicThemeRoutes() {
        return routeRepository.findByPublishedTrueOrderBySortOrderAscIdAsc().stream()
            .map(ContentLibraryService::toPublicRoute)
            .toList();
    }

    /**
     * 旧版首页要的 corridors。
     *
     * 优先由运营维护的 theme_route 派生；一条都没有时退回内置目录 ——
     * 首次部署、内容还没录的库不应该让旧客户端首页空掉。
     */
    @Transactional(readOnly = true)
    public List<TravelModels.Corridor> legacyCorridors() {
        List<ThemeRouteEntity> rows = routeRepository.findByPublishedTrueOrderBySortOrderAscIdAsc();
        if (rows.isEmpty()) {
            return TravelCatalog.corridors();
        }
        return rows.stream()
            .map(row -> new TravelModels.Corridor(row.getId(), row.getTitle(), row.getSubtitle(),
                row.getCities(), row.getDuration(), row.getBudget(), row.getCoverUrl(),
                splitHighlights(row.getHighlights())))
            .toList();
    }

    @Transactional(readOnly = true)
    public List<TravelModels.CultureArticleSummary> publicCulturePreview() {
        return articleRepository.findByPublishedTrueOrderBySortOrderAscCreatedAtDesc().stream()
            .limit(CULTURE_PREVIEW_LIMIT)
            .map(ContentLibraryService::toSummary)
            .toList();
    }

    @Transactional(readOnly = true)
    public List<TravelModels.CultureArticleSummary> publicCulture(String category) {
        List<CultureArticleEntity> rows = category == null || category.isBlank()
            ? articleRepository.findByPublishedTrueOrderBySortOrderAscCreatedAtDesc()
            : articleRepository.findByPublishedTrueAndCategoryOrderBySortOrderAscCreatedAtDesc(category.trim());
        return rows.stream().map(ContentLibraryService::toSummary).toList();
    }

    @Transactional(readOnly = true)
    public Optional<TravelModels.CultureArticle> publicCultureArticle(String id) {
        return articleRepository.findById(id)
            .filter(CultureArticleEntity::isPublished)
            .map(ContentLibraryService::toArticle);
    }

    /**
     * 全部视觉槽的当前取值。
     *
     * 未配置的槽也返回（imageUrl 为空），这样客户端有一份稳定的槽清单，
     * 不需要自己写死"首页横幅叫什么"。
     */
    @Transactional(readOnly = true)
    public List<TravelModels.VisualResource> publicVisualResources() {
        List<TravelModels.VisualResource> result = new ArrayList<>(VISUAL_SLOTS.size());
        for (String slot : VISUAL_SLOTS) {
            AppVisualResourceEntity row = visualRepository.findById(slot).orElse(null);
            if (row == null || !row.isEnabled()) {
                result.add(new TravelModels.VisualResource(slot, null, null, null));
                continue;
            }
            result.add(new TravelModels.VisualResource(slot, blankToNull(row.getImageUrl()),
                row.getImageCredit(), row.getSourceUrl()));
        }
        return result;
    }

    // ---------- 运营台：视觉资源 ----------

    @Transactional(readOnly = true)
    public List<ContentModels.VisualResourceView> adminVisualResources() {
        List<ContentModels.VisualResourceView> result = new ArrayList<>(VISUAL_SLOTS.size());
        for (String slot : VISUAL_SLOTS) {
            AppVisualResourceEntity row = visualRepository.findById(slot).orElse(null);
            result.add(new ContentModels.VisualResourceView(slot,
                row == null ? null : row.getImageUrl(),
                row == null ? null : row.getImageCredit(),
                row == null ? null : row.getSourceUrl(),
                row == null || row.isEnabled(),
                row == null ? null : row.getUpdatedAt().toString()));
        }
        return result;
    }

    @Transactional
    public ContentModels.VisualResourceView saveVisualResource(String slot,
                                                               ContentModels.VisualResourceInput input) {
        String safeSlot = requireSlot(slot);
        AppVisualResourceEntity entity = visualRepository.findById(safeSlot)
            .orElseGet(() -> {
                AppVisualResourceEntity fresh = new AppVisualResourceEntity();
                fresh.setSlot(safeSlot);
                return fresh;
            });
        entity.setImageUrl(trimToNull(input.imageUrl()));
        entity.setImageCredit(trimToNull(input.imageCredit()));
        entity.setSourceUrl(trimToNull(input.sourceUrl()));
        entity.setEnabled(!Boolean.FALSE.equals(input.enabled()));
        AppVisualResourceEntity saved = visualRepository.save(entity);
        return new ContentModels.VisualResourceView(saved.getSlot(), saved.getImageUrl(),
            saved.getImageCredit(), saved.getSourceUrl(), saved.isEnabled(),
            saved.getUpdatedAt().toString());
    }

    // ---------- 运营台：主题路线 ----------

    @Transactional(readOnly = true)
    public List<ContentModels.ThemeRouteView> adminThemeRoutes() {
        return routeRepository.findAllByOrderBySortOrderAscIdAsc().stream()
            .map(ContentLibraryService::toRouteView)
            .toList();
    }

    @Transactional
    public ContentModels.ThemeRouteView createThemeRoute(ContentModels.ThemeRouteInput input) {
        ThemeRouteEntity entity = new ThemeRouteEntity();
        entity.setId(nextRouteId());
        applyRoute(entity, input);
        entity.setSortOrder(input.sortOrder() == null ? nextRouteSortOrder() : input.sortOrder());
        entity.setPublished(!Boolean.FALSE.equals(input.published()));
        return toRouteView(routeRepository.save(entity));
    }

    @Transactional
    public ContentModels.ThemeRouteView updateThemeRoute(String id, ContentModels.ThemeRouteInput input) {
        ThemeRouteEntity entity = requireRoute(id);
        applyRoute(entity, input);
        if (input.sortOrder() != null) {
            entity.setSortOrder(input.sortOrder());
        }
        if (input.published() != null) {
            entity.setPublished(input.published());
        }
        return toRouteView(routeRepository.save(entity));
    }

    @Transactional
    public void deleteThemeRoute(String id) {
        routeRepository.delete(requireRoute(id));
    }

    // ---------- 运营台：文化锦囊 ----------

    @Transactional(readOnly = true)
    public List<ContentModels.CultureArticleView> adminCultureArticles() {
        return articleRepository.findAllByOrderBySortOrderAscCreatedAtDesc().stream()
            .map(ContentLibraryService::toArticleView)
            .toList();
    }

    @Transactional(readOnly = true)
    public ContentModels.CultureArticleView adminCultureArticle(String id) {
        return toArticleView(requireArticle(id));
    }

    @Transactional
    public ContentModels.CultureArticleView createCultureArticle(ContentModels.CultureArticleInput input) {
        CultureArticleEntity entity = new CultureArticleEntity();
        entity.setId(nextArticleId());
        applyArticle(entity, input);
        entity.setSortOrder(input.sortOrder() == null ? nextArticleSortOrder() : input.sortOrder());
        entity.setPublished(!Boolean.FALSE.equals(input.published()));
        return toArticleView(articleRepository.save(entity));
    }

    @Transactional
    public ContentModels.CultureArticleView updateCultureArticle(String id,
                                                                 ContentModels.CultureArticleInput input) {
        CultureArticleEntity entity = requireArticle(id);
        applyArticle(entity, input);
        if (input.sortOrder() != null) {
            entity.setSortOrder(input.sortOrder());
        }
        if (input.published() != null) {
            entity.setPublished(input.published());
        }
        return toArticleView(articleRepository.save(entity));
    }

    @Transactional
    public void deleteCultureArticle(String id) {
        articleRepository.delete(requireArticle(id));
    }

    // ---------- 内部 ----------

    private static String requireSlot(String slot) {
        String candidate = slot == null ? "" : slot.trim().toUpperCase(Locale.ROOT);
        if (!VISUAL_SLOTS.contains(candidate)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VISUAL_SLOT_UNKNOWN",
                "未知的视觉资源槽：" + slot);
        }
        return candidate;
    }

    private ThemeRouteEntity requireRoute(String id) {
        return routeRepository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "THEME_ROUTE_NOT_FOUND", "主题路线不存在"));
    }

    private CultureArticleEntity requireArticle(String id) {
        return articleRepository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "CULTURE_ARTICLE_NOT_FOUND", "文章不存在"));
    }

    private static void applyRoute(ThemeRouteEntity entity, ContentModels.ThemeRouteInput input) {
        entity.setTitle(trim(input.title()));
        entity.setSubtitle(trim(input.subtitle()));
        entity.setCities(trimToNull(input.cities()));
        entity.setDuration(trimToNull(input.duration()));
        entity.setBudget(trimToNull(input.budget()));
        entity.setCoverUrl(trimToNull(input.coverUrl()));
        entity.setHighlights(joinHighlights(input.highlights()));
        entity.setPlanningPrompt(trimToNull(input.planningPrompt()));
        entity.setImageCredit(trimToNull(input.imageCredit()));
        entity.setSourceUrl(trimToNull(input.sourceUrl()));
    }

    private static void applyArticle(CultureArticleEntity entity, ContentModels.CultureArticleInput input) {
        entity.setTitle(trim(input.title()));
        entity.setSummary(trimToNull(input.summary()));
        entity.setContent(trim(input.content()));
        entity.setCategory(trim(input.category()));
        entity.setCoverUrl(trimToNull(input.coverUrl()));
        entity.setImageCredit(trimToNull(input.imageCredit()));
        entity.setSourceUrl(trimToNull(input.sourceUrl()));
        entity.setAuthor(trimToNull(input.author()));
        if (input.likeCount() != null) {
            entity.setLikeCount(Math.max(0, input.likeCount()));
        }
    }

    private int nextRouteSortOrder() {
        return routeRepository.findAllByOrderBySortOrderAscIdAsc().stream()
            .mapToInt(ThemeRouteEntity::getSortOrder).max().orElse(0) + 10;
    }

    private int nextArticleSortOrder() {
        return articleRepository.findAllByOrderBySortOrderAscCreatedAtDesc().stream()
            .mapToInt(CultureArticleEntity::getSortOrder).max().orElse(0) + 10;
    }

    private String nextRouteId() {
        return uniqueId("route", routeRepository::existsById);
    }

    private String nextArticleId() {
        return uniqueId("culture", articleRepository::existsById);
    }

    private static String uniqueId(String prefix, java.util.function.Predicate<String> exists) {
        String base = prefix + "-" + Long.toHexString(System.nanoTime());
        String candidate = base;
        int suffix = 1;
        while (exists.test(candidate) && suffix < 100) {
            candidate = base + "-" + suffix++;
        }
        return candidate;
    }

    private static TravelModels.ThemeRoute toPublicRoute(ThemeRouteEntity entity) {
        return new TravelModels.ThemeRoute(entity.getId(), entity.getTitle(), entity.getSubtitle(),
            entity.getCities(), entity.getDuration(), entity.getBudget(), entity.getCoverUrl(),
            splitHighlights(entity.getHighlights()), entity.getPlanningPrompt(),
            entity.getImageCredit(), entity.getSourceUrl());
    }

    private static ContentModels.ThemeRouteView toRouteView(ThemeRouteEntity entity) {
        return new ContentModels.ThemeRouteView(entity.getId(), entity.getTitle(), entity.getSubtitle(),
            entity.getCities(), entity.getDuration(), entity.getBudget(), entity.getCoverUrl(),
            splitHighlights(entity.getHighlights()), entity.getPlanningPrompt(),
            entity.getImageCredit(), entity.getSourceUrl(), entity.isPublished(),
            entity.getSortOrder(), entity.getUpdatedAt() == null ? null : entity.getUpdatedAt().toString());
    }

    private static TravelModels.CultureArticleSummary toSummary(CultureArticleEntity entity) {
        return new TravelModels.CultureArticleSummary(entity.getId(), entity.getTitle(), entity.getSummary(),
            entity.getCategory(), entity.getCoverUrl(), entity.getImageCredit(), entity.getSourceUrl(),
            instant(entity.getUpdatedAt()), readingMinutes(entity.getContent()),
            entity.getAuthor(), entity.getLikeCount());
    }

    /**
     * 阅读时长（分钟）。
     *
     * <p>服务端按正文字数估算（中文约每分钟 350 字），最少 1 分钟。放在这里算，
     * 是因为只有服务端手上有正文：让运营台再填一个"阅读 X 分钟"，既可能和正文
     * 对不上，也白白增加录入负担。
     */
    private static int readingMinutes(String content) {
        String text = content == null ? "" : content.trim();
        return Math.max(1, (int) Math.round(text.length() / 350.0));
    }

    private static TravelModels.CultureArticle toArticle(CultureArticleEntity entity) {
        return new TravelModels.CultureArticle(entity.getId(), entity.getTitle(), entity.getSummary(),
            entity.getContent(), entity.getCategory(), entity.getCoverUrl(), entity.getImageCredit(),
            entity.getSourceUrl(), instant(entity.getUpdatedAt()),
            entity.getAuthor(), entity.getLikeCount());
    }

    private static ContentModels.CultureArticleView toArticleView(CultureArticleEntity entity) {
        return new ContentModels.CultureArticleView(entity.getId(), entity.getTitle(), entity.getSummary(),
            entity.getContent(), entity.getCategory(), entity.getCoverUrl(), entity.getImageCredit(),
            entity.getSourceUrl(), entity.isPublished(), entity.getSortOrder(),
            instant(entity.getCreatedAt()), instant(entity.getUpdatedAt()),
            entity.getAuthor(), entity.getLikeCount());
    }

    private static List<String> splitHighlights(String raw) {
        if (raw == null || raw.isBlank()) {
            return List.of();
        }
        return Arrays.stream(raw.split(","))
            .map(String::trim)
            .filter(value -> !value.isEmpty())
            .toList();
    }

    private static String joinHighlights(List<String> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }
        List<String> cleaned = values.stream()
            .map(value -> value == null ? "" : value.trim())
            .filter(value -> !value.isEmpty())
            .toList();
        return cleaned.isEmpty() ? null : String.join(",", cleaned);
    }

    private static String instant(Instant value) {
        return value == null ? null : value.toString();
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
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
}
