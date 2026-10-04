package com.yujian.travel.service;

import com.yujian.travel.api.TravelCatalog;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.domain.CultureArticleEntity;
import com.yujian.travel.domain.ThemeRouteEntity;
import com.yujian.travel.repository.CultureArticleRepository;
import com.yujian.travel.repository.ThemeRouteRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 内容库首次启动的兜底数据。
 *
 * 只在表为空时写入：运营台之后的增删改不会被重启覆盖。存在的意义是让
 * "新克隆一个库"的开发者和"刚部署到云上"的环境都有一个能直接演示的首页，
 * 而不是空白页。
 *
 * 三条主题路线与原硬编码的走廊一致（MySQL 上 V6 已经写过一遍，这里靠
 * "表为空"判断天然幂等）；文化锦囊是项目组自己整理的三篇入门文章，
 * 不转述无来源的数据，运营台可以随时替换。
 */
@Component
public class ContentLibrarySeeder implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(ContentLibrarySeeder.class);

    private final ThemeRouteRepository routeRepository;
    private final CultureArticleRepository articleRepository;

    public ContentLibrarySeeder(ThemeRouteRepository routeRepository,
                                CultureArticleRepository articleRepository) {
        this.routeRepository = routeRepository;
        this.articleRepository = articleRepository;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        int routes = seedRoutes();
        int articles = seedArticles();
        if (routes > 0 || articles > 0) {
            log.info("Seeded {} theme routes and {} culture articles", routes, articles);
        }
    }

    private int seedRoutes() {
        if (routeRepository.count() > 0) {
            return 0;
        }
        int sortOrder = 10;
        List<TravelModels.Corridor> corridors = TravelCatalog.corridors();
        for (TravelModels.Corridor corridor : corridors) {
            ThemeRouteEntity entity = new ThemeRouteEntity();
            entity.setId(corridor.id());
            entity.setTitle(corridor.title());
            entity.setSubtitle(corridor.subtitle());
            entity.setCities(corridor.cities());
            entity.setDuration(corridor.duration());
            entity.setBudget(corridor.budget());
            entity.setCoverUrl(corridor.imageUrl());
            entity.setHighlights(String.join(",", corridor.highlights()));
            entity.setPlanningPrompt(planningPromptFor(corridor));
            entity.setPublished(true);
            entity.setSortOrder(sortOrder);
            entity.setImageCredit(TravelCatalog.DEMO_IMAGE_CREDIT);
            entity.setSourceUrl(TravelCatalog.DEMO_IMAGE_SOURCE);
            sortOrder += 10;
            routeRepository.save(entity);
        }
        return corridors.size();
    }

    private static String planningPromptFor(TravelModels.Corridor corridor) {
        return "沿着" + corridor.title() + "走一趟，" + corridor.subtitle() + "。";
    }

    private int seedArticles() {
        if (articleRepository.count() > 0) {
            return 0;
        }
        List<CultureArticleEntity> articles = List.of(
            article("culture-luoyang-first", "中原历史", "第一次去洛阳，先看懂这三处",
                "龙门石窟、洛阳博物馆、白马寺，三处放在一起，洛阳的一千五百年就有了一条主线。",
                "洛阳是十三朝古都，但第一次去很容易只记住\u201C到处都是古迹\u201D。\n\n"
                    + "龙门石窟看的是石刻造像的演变：从北魏的清瘦到唐代的丰腴，一壁之间能看到审美怎么变。建议留出三到四小时，沿伊河两岸慢慢走。\n\n"
                    + "洛阳博物馆看的是\u201C这些东西从哪来\u201D：把前面看到的石窟、青铜、唐三彩放回时间线里。\n\n"
                    + "白马寺看的是佛教东传的起点。三处连起来，就不是打卡，而是一条能自己讲下去的线索。\n\n"
                    + "（本文由项目组整理，仅供行前了解；开放时间与预约要求请以景区公告为准。）",
                10),
            article("culture-henan-food", "河南美食", "河南旅行吃什么：一份不踩坑的入门清单",
                "胡辣汤、烩面、灌汤包、洛阳水席——先把名字记住，再按城市找。",
                "河南的饮食很\u201C日常\u201D，不是靠摆盘取胜，而是靠一顿饭把一天撑起来。\n\n"
                    + "早餐可以从胡辣汤开始，配油条或水煎包；午饭一碗烩面足够顶到晚上。\n\n"
                    + "到开封，灌汤包和小宋城一带的夜市值得留一个晚上；到洛阳，水席是仪式感最强的一顿，人多的时候点起来更划算。\n\n"
                    + "口味上普遍偏咸鲜，怕辣或不爱吃香菜的，点单前说一声就行。\n\n"
                    + "（本文由项目组整理，具体店家与营业时间请以现场为准。）",
                20),
            article("culture-before-you-go", "行前准备", "来河南之前，先把这几件事想清楚",
                "天气、交通、预约，三件事想清楚，行程就顺了。",
                "河南的景点分两类：一类在城里，一类在山上。城里的博物馆、古建基本不受天气影响；山里的云台山、嵩山则对降雨和大风很敏感。\n\n"
                    + "跨城优先看高铁：郑州、开封、洛阳之间车次密，把住宿订在车站附近，能省下不少时间。市内则优先地铁与公交。\n\n"
                    + "热门景区常常需要提前预约，门票与开放时间请以官方渠道为准。\n\n"
                    + "最后，行程不要排太满。河南很多地方值得慢下来，一天两到三个点，比一整天赶五个点舒服得多。\n\n"
                    + "（本文由项目组整理，仅供行前参考。）",
                30)
        );
        articleRepository.saveAll(articles);
        return articles.size();
    }

    private static CultureArticleEntity article(String id, String category, String title,
                                                String summary, String content, int sortOrder) {
        CultureArticleEntity entity = new CultureArticleEntity();
        entity.setId(id);
        entity.setCategory(category);
        entity.setTitle(title);
        entity.setSummary(summary);
        entity.setContent(content);
        entity.setPublished(true);
        entity.setSortOrder(sortOrder);
        entity.setImageCredit("内容由项目组整理");
        return entity;
    }
}
