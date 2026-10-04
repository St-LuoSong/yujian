package com.yujian.travel.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * 每个请求都会经过的护栏：体积上限 + 限流。
 *
 * 两件事合在一个过滤器里，是因为它们都必须在**业务代码之前**、而且都需要
 * "每个请求看一眼"；拆成两个只会让执行顺序变成又一个要记住的前提。
 *
 * 顺序写在 Spring Security 过滤器链之后（security 链是 -100，这里是 0）：
 * 这样才拿得到已经解析出来的登录用户；未通过鉴权的请求会先被安全链拒绝，
 * 既不浪费一次计数，也不占用护栏的开销。
 */
@Component
@Order(0)
public class RequestGuardFilter extends OncePerRequestFilter {
    /**
     * 非上传类请求的体积上限。
     *
     * JSON 请求体不受容器默认值约束（`max-http-form-post-size` 只管表单），
     * 一个几百 MB 的 body 会被直接读进内存。上传走的是 multipart，由各自的
     * 业务上限管，不在这里判。
     */
    private static final long MAX_BODY_BYTES = 1L * 1024 * 1024;

    private static final Pattern AUTH_PATH =
        Pattern.compile("^/api/(auth/(login|register|refresh)|email/.*)$");
    private static final Pattern MEDIA_PATH =
        Pattern.compile("^/api/(community/media|admin/media|auth/me/avatar).*$");
    private static final Pattern PLAN_PATH = Pattern.compile("^/api/trip-plans(/.*)?$");

    private final RateLimitService limiter;
    private final ObjectMapper objectMapper;

    public RequestGuardFilter(RateLimitService limiter, ObjectMapper objectMapper) {
        this.limiter = limiter;
        this.objectMapper = objectMapper;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String uri = request.getRequestURI();
        return "OPTIONS".equalsIgnoreCase(request.getMethod())
            // 静态资源与健康检查不计数：它们既不走业务，也不消耗外部额度。
            || uri.startsWith("/media/")
            || uri.startsWith("/actuator/")
            || uri.startsWith("/share/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        List<String> buckets = bucketsFor(request);
        if (!buckets.isEmpty()) {
            RateLimitService.Decision decision = limiter.check(buckets, identity(request));
            if (!decision.allowed()) {
                rejectTooManyRequests(response, decision);
                return;
            }
        }
        if (bodyTooLarge(request)) {
            rejectTooLarge(response);
            return;
        }
        chain.doFilter(request, response);
    }

    private static boolean bodyTooLarge(HttpServletRequest request) {
        String contentType = request.getContentType();
        if (contentType != null && contentType.toLowerCase(Locale.ROOT).startsWith("multipart/")) {
            return false;
        }
        return request.getContentLengthLong() > MAX_BODY_BYTES;
    }

    private void rejectTooLarge(HttpServletResponse response) throws IOException {
        response.setStatus(413);
        response.setCharacterEncoding("UTF-8");
        response.setContentType("application/json;charset=UTF-8");
        objectMapper.writeValue(response.getWriter(), Map.of(
            "code", "PAYLOAD_TOO_LARGE",
            "message", "请求内容过大"));
    }

    private void rejectTooManyRequests(HttpServletResponse response,
                                       RateLimitService.Decision decision) throws IOException {
        // Servlet 的常量表里没有 429（它是 HTTP/1.1 后期补的状态码），写数字。
        response.setStatus(429);
        response.setHeader("Retry-After", String.valueOf(decision.retryAfterSeconds()));
        response.setCharacterEncoding("UTF-8");
        response.setContentType("application/json;charset=UTF-8");
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("code", "RATE_LIMITED");
        body.put("message", "请求过于频繁，请 " + decision.retryAfterSeconds() + " 秒后再试");
        body.put("bucket", decision.bucket());
        objectMapper.writeValue(response.getWriter(), body);
    }

    /**
     * 请求落在哪个桶里。
     *
     * 生成行程同时挂"每分钟"与"每日"两个桶：前者防连点，后者是大模型开销的硬上限。
     */
    private static List<String> bucketsFor(HttpServletRequest request) {
        String uri = request.getRequestURI();
        if (!uri.startsWith("/api/")) {
            return List.of();
        }
        String method = request.getMethod().toUpperCase(Locale.ROOT);
        if ("GET".equals(method) || "HEAD".equals(method)) {
            return List.of("read");
        }
        if (PLAN_PATH.matcher(uri).matches()) {
            return List.of("plan", "plan-daily");
        }
        if ("POST".equals(method) && AUTH_PATH.matcher(uri).matches()) {
            return List.of("auth");
        }
        if (MEDIA_PATH.matcher(uri).matches()) {
            return List.of("media");
        }
        return List.of("write");
    }

    /**
     * 限流的主体。
     *
     * 登录用户按账号计，其余按客户端 IP —— 账号是不可伪造的，比 IP 可靠得多。
     */
    private static String identity(HttpServletRequest request) {
        AuthUser user = CurrentUser.userOrNull();
        if (user != null && user.id() != null) {
            return "u:" + user.id();
        }
        return "ip:" + clientIp(request);
    }

    /**
     * 取客户端 IP。
     *
     * `X-Forwarded-For` 是客户端可以随便写的头。只有当直连我们的是一个内网地址
     * （也就是我们自己的反向代理）时才采信它；公网直连的场景一律用 TCP 层的地址。
     * 否则任何人换着 XFF 就能绕开限流。
     */
    private static String clientIp(HttpServletRequest request) {
        String remote = request.getRemoteAddr();
        if (!isPrivateAddress(remote)) {
            return remote;
        }
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            int comma = forwarded.indexOf(',');
            String first = (comma < 0 ? forwarded : forwarded.substring(0, comma)).trim();
            if (!first.isEmpty()) {
                return first;
            }
        }
        return remote;
    }

    private static boolean isPrivateAddress(String address) {
        if (address == null || address.isBlank()) {
            return false;
        }
        return address.startsWith("10.")
            || address.startsWith("192.168.")
            || address.startsWith("127.")
            || address.startsWith("172.16.") || address.startsWith("172.17.")
            || address.startsWith("172.18.") || address.startsWith("172.19.")
            || address.startsWith("172.2") || address.startsWith("172.30.")
            || address.startsWith("172.31.")
            || "::1".equals(address);
    }
}
