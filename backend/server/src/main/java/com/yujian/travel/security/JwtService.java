package com.yujian.travel.security;

import com.yujian.travel.config.AppProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.Date;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

@Service
public class JwtService {
    private final AppProperties properties;
    private final SecretKey signingKey;

    public JwtService(AppProperties properties) {
        this.properties = properties;
        this.signingKey = Keys.hmacShaKeyFor(sha256(properties.getJwt().getSecret()));
    }

    public String createAccessToken(UUID userId, String username, Set<String> roles) {
        Instant now = Instant.now();
        Instant expiresAt = now.plusSeconds(properties.getJwt().getAccessMinutes() * 60);
        return Jwts.builder()
            .subject(userId.toString())
            .claims(Map.of("type", "access", "username", username, "roles", roles))
            .issuedAt(Date.from(now))
            .expiration(Date.from(expiresAt))
            .signWith(signingKey)
            .compact();
    }

    public String createRefreshToken(UUID userId) {
        Instant now = Instant.now();
        Instant expiresAt = now.plusSeconds(properties.getJwt().getRefreshDays() * 86_400);
        return Jwts.builder()
            .subject(userId.toString())
            .id(UUID.randomUUID().toString())
            .claim("type", "refresh")
            .issuedAt(Date.from(now))
            .expiration(Date.from(expiresAt))
            .signWith(signingKey)
            .compact();
    }

    public Claims parse(String token) {
        return Jwts.parser()
            .verifyWith(signingKey)
            .build()
            .parseSignedClaims(token)
            .getPayload();
    }

    public boolean isType(Claims claims, String expectedType) {
        return expectedType.equals(claims.get("type", String.class));
    }

    public Instant refreshExpiresAt(String token) {
        return parse(token).getExpiration().toInstant();
    }

    public long accessTokenSeconds() {
        return properties.getJwt().getAccessMinutes() * 60;
    }

    private byte[] sha256(String value) {
        try {
            return MessageDigest.getInstance("SHA-256")
                .digest(value.getBytes(StandardCharsets.UTF_8));
        } catch (Exception exception) {
            throw new IllegalStateException("无法初始化 JWT 密钥", exception);
        }
    }
}
