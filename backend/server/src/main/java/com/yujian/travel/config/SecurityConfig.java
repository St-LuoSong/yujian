package com.yujian.travel.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.security.AnonymousAuthenticationFilter;
import com.yujian.travel.security.JwtAuthenticationFilter;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.time.Instant;
import java.util.List;
import java.util.Map;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, JwtAuthenticationFilter jwtFilter,
                                                   AnonymousAuthenticationFilter anonymousFilter,
                                                   AppProperties properties,
                                                   ObjectMapper objectMapper) throws Exception {
        http
            .csrf(AbstractHttpConfigurer::disable)
            .cors(cors -> cors.configurationSource(corsConfigurationSource(properties)))
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(authorize -> authorize
                .requestMatchers("/api/auth/**", "/api/home", "/api/pois/**",
                    "/api/anonymous/session", "/actuator/health",
                    // Version checks and verified APK downloads must work before sign-in.
                    "/api/app-releases/**",
                    // 只读分享页对浏览器公开：接收者不应为了看一份行程去注册账号。
                    "/share/**",
                    // 运营台上传的景点配图通过只读路径公开，写入仍然只在 /api/admin/** 下。
                    "/media/**",
                    // 行程底图由 CachedNetworkImage 直接拉取，带不了 Authorization 头。
                    // 它的访问控制不是"登录"，而是"服务端签发的一次性短时票据"：
                    // 只为已经通过归属校验的快照签发，过期即失效，见 MapTicketService。
                    "/api/map/image").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/trip-plans/preview", "/api/trip-plans",
                    // 反馈允许匿名提交，服务端只保存内容与可选联系方式。
                    "/api/feedback").permitAll()
                .requestMatchers(HttpMethod.GET, "/api/trip-shares/*").permitAll()
                // 社区公开信息流与详情不要求登录；发布、点赞和举报仍然必须登录。
                .requestMatchers(HttpMethod.GET, "/api/community/posts", "/api/community/posts/*",
                    // 评论跟详情页一样是公开只读的；发言仍然要登录。
                    "/api/community/posts/*/comments").permitAll()
                .requestMatchers(HttpMethod.POST, "/api/email/**").permitAll()
                // Operator endpoints. The bootstrap account is created from
                // ADMIN_USERNAME / ADMIN_PASSWORD, so this is never public.
                .requestMatchers("/api/admin/**").hasRole("ADMIN")
                .anyRequest().authenticated())
            .exceptionHandling(exceptions -> exceptions
                .authenticationEntryPoint((request, response, exception) ->
                    writeError(response, objectMapper, HttpServletResponse.SC_UNAUTHORIZED,
                        "AUTH_REQUIRED", "请先登录或创建匿名会话"))
                .accessDeniedHandler((request, response, exception) ->
                    writeError(response, objectMapper, HttpServletResponse.SC_FORBIDDEN,
                        "ACCESS_DENIED", "当前账号无权执行该操作")))
            .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(anonymousFilter, JwtAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource(AppProperties properties) {
        CorsConfiguration configuration = new CorsConfiguration();
        configuration.setAllowedOrigins(properties.getCors().getAllowedOrigins());
        configuration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        configuration.setAllowedHeaders(List.of("Authorization", "Content-Type", "X-Anonymous-Token",
            "X-Device-Fingerprint"));
        configuration.setExposedHeaders(List.of("X-Anonymous-Token"));
        configuration.setAllowCredentials(true);
        configuration.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", configuration);
        return source;
    }

    private void writeError(HttpServletResponse response, ObjectMapper objectMapper, int status,
                            String code, String message) throws java.io.IOException {
        response.setStatus(status);
        response.setCharacterEncoding("UTF-8");
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        objectMapper.writeValue(response.getWriter(),
            Map.of("code", code, "message", message, "timestamp", Instant.now().toString()));
    }
}
