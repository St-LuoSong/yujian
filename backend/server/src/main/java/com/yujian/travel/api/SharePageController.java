package com.yujian.travel.api;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.service.TripShareService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;

import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * 公开只读分享页。
 *
 * 接收者不需要登录、不需要安装 App，用手机浏览器打开链接就能看到这份行程。
 * 页面只渲染服务端已经脱敏过的内容（隐藏预算时金额已经是 0），
 * 不输出令牌、账号、备注或任何第三方密钥；所有文本都做 HTML 转义，避免行程标题成为注入点。
 */
@Controller
@RequestMapping("/share")
public class SharePageController {
    private static final MediaType HTML_UTF8 = new MediaType(MediaType.TEXT_HTML, StandardCharsets.UTF_8);

    private final TripShareService tripShareService;

    public SharePageController(TripShareService tripShareService) {
        this.tripShareService = tripShareService;
    }

    @GetMapping("/{token}")
    public ResponseEntity<String> page(@PathVariable String token) {
        try {
            return html(HttpStatus.OK, render(tripShareService.view(token)));
        } catch (ApiException ex) {
            return html(ex.getStatus(), errorPage(ex.getMessage()));
        } catch (RuntimeException ex) {
            // 不把异常细节回显到公开页面，避免泄露内部实现。
            return html(HttpStatus.INTERNAL_SERVER_ERROR, errorPage("分享页面暂时不可用，请稍后再试"));
        }
    }

    private static ResponseEntity<String> html(HttpStatus status, String body) {
        return ResponseEntity.status(status).contentType(HTML_UTF8).body(body);
    }

    private static String render(TripPlanModels.SharedTrip shared) {
        TravelModels.TripPlan plan = shared.plan();
        StringBuilder days = new StringBuilder();
        for (TravelModels.TripDay day : plan.days()) {
            days.append("<section class=\"day\">");
            days.append("<h2 class=\"day-head\"><span class=\"day-label\">").append(esc(day.label())).append("</span>");
            if (day.date() != null && !day.date().isBlank()) {
                days.append("<span class=\"day-note\">").append(esc(day.date())).append("</span>");
            }
            days.append("</h2><ol class=\"timeline\">");
            for (TravelModels.TripItem item : day.items()) {
                days.append("<li class=\"stop\"><div class=\"stop-time\">").append(esc(item.time())).append("</div>");
                days.append("<div class=\"stop-body\"><h3>").append(esc(item.title())).append("</h3>");
                if (item.description() != null && !item.description().isBlank()) {
                    days.append("<p class=\"stop-desc\">").append(esc(item.description())).append("</p>");
                }
                days.append("<p class=\"stop-meta\">");
                appendMeta(days, item.duration());
                appendMeta(days, item.transport());
                if (!shared.hideBudget() && item.cost() > 0) {
                    appendMeta(days, "¥" + item.cost());
                }
                days.append("</p>");
                if (item.risk() != null && !item.risk().isBlank()) {
                    days.append("<p class=\"stop-risk\">注意：").append(esc(item.risk())).append("</p>");
                }
                days.append("<p class=\"stop-src\">来源 ").append(esc(orDash(item.source())))
                    .append(" · 状态 ").append(esc(orDash(item.dataStatus()))).append("</p>");
                days.append("</div></li>");
            }
            days.append("</ol></section>");
        }

        StringBuilder warnings = new StringBuilder();
        List<String> planWarnings = plan.warnings();
        if (planWarnings != null && !planWarnings.isEmpty()) {
            warnings.append("<section class=\"warnings\"><h2>出行提醒</h2><ul>");
            for (String warning : planWarnings) {
                warnings.append("<li>").append(esc(warning)).append("</li>");
            }
            warnings.append("</ul></section>");
        }

        String budget = shared.hideBudget()
            ? "<div class=\"fact\"><dt>费用</dt><dd>分享者已隐藏</dd></div>"
            : "<div class=\"fact\"><dt>人均参考</dt><dd>¥" + esc(String.valueOf(plan.perPersonCost()))
                + "</dd></div>";

        return SHELL.replace("{{TITLE}}", esc(plan.title()))
            .replace("{{DOC_TITLE}}", esc(plan.title()) + " · 豫见智旅")
            .replace("{{SUMMARY}}", esc(plan.summary()))
            .replace("{{CORRIDOR}}", esc(orDash(plan.corridor())))
            .replace("{{DAYS}}", esc(String.valueOf(plan.days().size())))
            .replace("{{INTENSITY}}", esc(orDash(plan.intensity())))
            .replace("{{BUDGET}}", budget)
            .replace("{{STATUS}}", esc(orDash(plan.dataStatus())))
            .replace("{{DAYS_BODY}}", days.toString())
            .replace("{{WARNINGS}}", warnings.toString());
    }

    private static void appendMeta(StringBuilder target, String value) {
        if (value != null && !value.isBlank()) {
            target.append("<span>").append(esc(value)).append("</span>");
        }
    }

    private static String errorPage(String message) {
        return ERROR_SHELL.replace("{{MESSAGE}}", esc(message == null ? "分享链接不可用" : message));
    }

    private static String orDash(String value) {
        return value == null || value.isBlank() ? "—" : value;
    }

    private static String esc(String value) {
        if (value == null) {
            return "";
        }
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            .replace("\"", "&quot;").replace("'", "&#39;");
    }

    private static final String STYLE = """
        :root{--ink:#1B2422;--glaze:#EFF1EE;--celadon:#3F6F6A;--celadon-soft:#C9D8D3;--ash:#7C8B87;--kiln:#A8341E}
        *{box-sizing:border-box}
        body{margin:0;background:var(--glaze);color:var(--ink);
             font-family:-apple-system,BlinkMacSystemFont,'PingFang SC','Microsoft YaHei','Source Han Sans SC',sans-serif;
             line-height:1.65;-webkit-font-smoothing:antialiased}
        a{color:var(--celadon)}
        .wrap{max-width:720px;margin:0 auto;padding:0 20px 64px}
        .bar{position:sticky;top:0;z-index:5;background:rgba(239,241,238,.92);border-bottom:1px solid var(--celadon-soft);
             backdrop-filter:saturate(140%) blur(8px)}
        .bar-in{max-width:720px;margin:0 auto;padding:12px 20px;display:flex;align-items:center;justify-content:space-between}
        .brand{font-weight:600;letter-spacing:.14em}
        .tag{font-size:12px;color:var(--ash);letter-spacing:.08em}
        .eyebrow{margin:32px 0 8px;font-size:12px;letter-spacing:.24em;color:var(--ash)}
        h1{margin:0 0 12px;font-size:27px;line-height:1.3;font-weight:600}
        .summary{margin:0 0 26px;color:#3A4442}
        .facts{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:1px;margin:0 0 34px;
               background:var(--celadon-soft);border:1px solid var(--celadon-soft)}
        .fact{background:var(--glaze);padding:12px 14px}
        .fact dt{font-size:12px;color:var(--ash);letter-spacing:.08em}
        .fact dd{margin:2px 0 0;font-size:17px;font-variant-numeric:tabular-nums;font-feature-settings:'tnum' 1}
        .warnings{margin:0 0 30px;padding:14px 16px;border-left:2px solid var(--kiln);background:#F4EFEC}
        .warnings h2{margin:0 0 6px;font-size:14px;letter-spacing:.1em;color:var(--kiln)}
        .warnings ul{margin:0;padding-left:18px;font-size:14px}
        .day{margin:0 0 34px}
        .day-head{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin:0 0 12px;
                  padding-bottom:8px;border-bottom:1px solid var(--celadon-soft);font-size:16px}
        .day-label{font-weight:600;letter-spacing:.06em}
        .day-note{font-size:13px;color:var(--ash)}
        .timeline{list-style:none;margin:0;padding:0}
        .stop{display:grid;grid-template-columns:64px 1fr;gap:14px;padding:0 0 18px;position:relative}
        .stop::before{content:'';position:absolute;left:63px;top:6px;bottom:-4px;width:1px;background:var(--celadon-soft)}
        .stop:last-child::before{display:none}
        .stop-time{padding-top:2px;font-size:13px;color:var(--ash);text-align:right;
                   font-variant-numeric:tabular-nums;font-feature-settings:'tnum' 1}
        .stop-body{position:relative;padding-left:14px}
        .stop-body::before{content:'';position:absolute;left:0;top:8px;width:7px;height:7px;border-radius:50%;
                           background:var(--celadon);box-shadow:0 0 0 3px var(--glaze)}
        .stop-body h3{margin:0 0 4px;font-size:16px;font-weight:600}
        .stop-desc{margin:0 0 6px;font-size:14px;color:#3A4442}
        .stop-meta{margin:0 0 4px;display:flex;flex-wrap:wrap;gap:6px;font-size:12px;color:var(--ash);
                   font-variant-numeric:tabular-nums}
        .stop-meta span{padding:1px 8px;border:1px solid var(--celadon-soft)}
        /* 风险只在左侧保留一条朱色细线：一屏内朱色不重复铺满文字。 */
        .stop-risk{margin:6px 0 0;padding-left:8px;border-left:2px solid var(--kiln);font-size:13px;color:var(--ink-soft)}
        .stop-src{margin:6px 0 0;font-size:12px;color:var(--ash)}
        .foot{margin-top:40px;padding-top:16px;border-top:1px solid var(--celadon-soft);font-size:12px;color:var(--ash)}
        @media (max-width:420px){h1{font-size:23px}.stop{grid-template-columns:54px 1fr}.stop::before{left:53px}}
        @media (prefers-reduced-motion:reduce){*{transition:none!important;animation:none!important}}
        """;

    private static final String SHELL = "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n"
        + "<meta charset=\"utf-8\">\n"
        + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">\n"
        + "<meta name=\"robots\" content=\"noindex,nofollow\">\n"
        + "<title>{{DOC_TITLE}}</title>\n<style>" + STYLE + "</style>\n</head>\n<body>\n"
        + "<header class=\"bar\"><div class=\"bar-in\"><span class=\"brand\">豫见智旅</span>"
        + "<span class=\"tag\">只读分享</span></div></header>\n"
        + "<div class=\"wrap\">\n"
        + "<p class=\"eyebrow\">河南 · 行程单</p>\n"
        + "<h1>{{TITLE}}</h1>\n"
        + "<p class=\"summary\">{{SUMMARY}}</p>\n"
        + "<dl class=\"facts\">"
        + "<div class=\"fact\"><dt>走廊</dt><dd>{{CORRIDOR}}</dd></div>"
        + "<div class=\"fact\"><dt>天数</dt><dd>{{DAYS}} 天</dd></div>"
        + "<div class=\"fact\"><dt>节奏</dt><dd>{{INTENSITY}}</dd></div>"
        + "{{BUDGET}}"
        + "</dl>\n"
        + "{{WARNINGS}}"
        + "{{DAYS_BODY}}"
        + "<p class=\"foot\">数据状态：{{STATUS}}。本页面为只读分享，调整与保存请在「豫见智旅」App 中完成。"
        + "行程中的开放时间、票价与交通信息均为参考，出行前请以景区和铁路官方渠道为准。</p>\n"
        + "</div>\n</body>\n</html>";

    private static final String ERROR_SHELL = "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n"
        + "<meta charset=\"utf-8\">\n"
        + "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
        + "<meta name=\"robots\" content=\"noindex,nofollow\">\n"
        + "<title>分享不可用 · 豫见智旅</title>\n<style>" + STYLE + "\n"
        + ".err{max-width:420px;margin:22vh auto 0;padding:0 24px;text-align:center}\n"
        + ".err h1{font-size:20px;margin-bottom:10px}\n"
        + ".err p{color:var(--ash);font-size:14px}\n"
        + "</style>\n</head>\n<body>\n"
        + "<div class=\"err\"><p class=\"eyebrow\">豫见智旅</p><h1>这个分享暂时打不开</h1>"
        + "<p>{{MESSAGE}}</p><p>可以让分享者重新生成一条只读链接。</p></div>\n</body>\n</html>";
}
