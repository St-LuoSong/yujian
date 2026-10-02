package com.yujian.travel.security;

import com.yujian.travel.domain.AnonymousSession;
import com.yujian.travel.repository.AnonymousSessionRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

@Component
public class AnonymousAuthenticationFilter extends OncePerRequestFilter {
    public static final String ANONYMOUS_TOKEN_HEADER = "X-Anonymous-Token";

    private final AnonymousSessionRepository anonymousSessionRepository;

    public AnonymousAuthenticationFilter(AnonymousSessionRepository anonymousSessionRepository) {
        this.anonymousSessionRepository = anonymousSessionRepository;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
        throws ServletException, IOException {
        if (SecurityContextHolder.getContext().getAuthentication() == null) {
            String rawToken = request.getHeader(ANONYMOUS_TOKEN_HEADER);
            if (rawToken != null && !rawToken.isBlank()) {
                resolve(rawToken).ifPresent(session -> {
                    AnonymousPrincipal principal = new AnonymousPrincipal(session.getId());
                    UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                        principal, null, List.of(new SimpleGrantedAuthority("ROLE_ANONYMOUS")));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                });
            }
        }
        filterChain.doFilter(request, response);
    }

    private Optional<AnonymousSession> resolve(String rawToken) {
        return anonymousSessionRepository.findByTokenHash(TokenHash.sha256Hex(rawToken))
            .filter(session -> session.getExpiresAt().isAfter(Instant.now()))
            .filter(session -> session.getConvertedUserId() == null);
    }
}
