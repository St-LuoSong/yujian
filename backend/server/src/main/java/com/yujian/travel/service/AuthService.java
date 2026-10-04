package com.yujian.travel.service;

import com.yujian.travel.api.AuthModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.RefreshToken;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.RefreshTokenRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.security.JwtService;
import com.yujian.travel.security.TokenHash;
import io.jsonwebtoken.Claims;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.time.Instant;
import java.util.List;
import java.util.Set;
import java.util.UUID;

@Service
public class AuthService {
    private static final Set<String> ALLOWED_AVATARS =
        Set.of("celadon", "kiln", "amber", "river", "ink");

    private final UserAccountRepository userRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final AccountDeletionService accountDeletionService;
    private final MediaStorageService mediaStorage;

    public AuthService(UserAccountRepository userRepository, RefreshTokenRepository refreshTokenRepository,
                       PasswordEncoder passwordEncoder, JwtService jwtService,
                       AccountDeletionService accountDeletionService,
                       MediaStorageService mediaStorage) {
        this.userRepository = userRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.accountDeletionService = accountDeletionService;
        this.mediaStorage = mediaStorage;
    }

    @Transactional
    public AuthModels.AuthResponse register(AuthModels.RegisterRequest request) {
        String username = request.username().trim();
        String email = request.email().trim().toLowerCase();
        if (userRepository.existsByUsernameIgnoreCase(username)) {
            throw new ApiException(HttpStatus.CONFLICT, "USERNAME_EXISTS", "该用户名已被使用");
        }
        if (userRepository.existsByEmailIgnoreCase(email)) {
            throw new ApiException(HttpStatus.CONFLICT, "EMAIL_EXISTS", "该邮箱已被注册");
        }
        UserAccount user = new UserAccount();
        user.setUsername(username);
        user.setEmail(email);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setEmailVerified(false);
        user.setRoles(Set.of("USER"));
        user = userRepository.save(user);
        return issueTokens(user);
    }

    @Transactional
    public AuthModels.AuthResponse login(AuthModels.LoginRequest request) {
        String identifier = request.identifier().trim();
        UserAccount user = userRepository.findByUsernameIgnoreCaseOrEmailIgnoreCase(identifier, identifier)
            .orElseThrow(this::invalidCredentials);
        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw invalidCredentials();
        }
        return issueTokens(user);
    }

    @Transactional
    public AuthModels.AuthResponse refresh(String rawRefreshToken) {
        Claims claims = parseRefresh(rawRefreshToken);
        UUID userId = UUID.fromString(claims.getSubject());
        RefreshToken stored = refreshTokenRepository.findByTokenHash(TokenHash.sha256Hex(rawRefreshToken))
            .orElseThrow(this::invalidRefreshToken);
        if (stored.isRevoked() || stored.getExpiresAt().isBefore(Instant.now())
            || !stored.getUser().getId().equals(userId)) {
            throw invalidRefreshToken();
        }
        UserAccount user = userRepository.findById(userId).orElseThrow(this::invalidRefreshToken);
        AuthModels.AuthResponse response = issueTokens(user);
        stored.setRevoked(true);
        stored.setRevokedAt(Instant.now());
        stored.setReplacedByHash(TokenHash.sha256Hex(response.refreshToken()));
        return response;
    }

    @Transactional
    public void logout(String rawRefreshToken) {
        if (rawRefreshToken == null || rawRefreshToken.isBlank()) {
            return;
        }
        refreshTokenRepository.findByTokenHash(TokenHash.sha256Hex(rawRefreshToken)).ifPresent(token -> {
            token.setRevoked(true);
            token.setRevokedAt(Instant.now());
        });
    }

    @Transactional(readOnly = true)
    public AuthModels.UserSummary me(UUID userId) {
        UserAccount user = userRepository.findById(userId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "登录状态已失效"));
        return summary(user);
    }

    @Transactional
    public AuthModels.UserSummary updateProfile(UUID userId, String rawNickname, String rawAvatarKey) {
        UserAccount user = requireUser(userId);
        String nickname = rawNickname == null ? null : rawNickname.trim();
        if (nickname != null && nickname.length() > 40) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "NICKNAME_TOO_LONG", "昵称不能超过 40 个字符");
        }
        String avatarKey = rawAvatarKey == null ? null : rawAvatarKey.trim();
        if (avatarKey != null && !avatarKey.isEmpty() && !ALLOWED_AVATARS.contains(avatarKey)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "AVATAR_KEY_INVALID", "头像标识不合法");
        }
        String previousAvatarUrl = user.getAvatarUrl();
        user.setNickname(nickname == null || nickname.isEmpty() ? null : nickname);
        user.setAvatarKey(avatarKey == null || avatarKey.isEmpty() ? null : avatarKey);
        // 明确选了预设图案就等于放弃自定义头像，否则用户点了预设却还看到旧照片。
        // avatarKey 为空是"没选预设"，这时自定义头像保持不动 —— 改个昵称不该把
        // 头像一起弄丢。
        if (user.getAvatarKey() != null) {
            user.setAvatarUrl(null);
        }
        AuthModels.UserSummary saved = summary(userRepository.save(user));
        deleteReplacedAvatar(previousAvatarUrl, user.getAvatarUrl());
        return saved;
    }

    /**
     * 上传自定义头像。
     *
     * 走与旅记图片同一条重编码链路：文件名由服务端生成、类型只看文件头、
     * 重新编码时丢掉 EXIF。存的是服务端相对路径而不是完整 URL —— 完整 URL 会把
     * "上传时那个主机名"写进数据库，换域名或换端口之后所有历史头像都会失效。
     */
    @Transactional
    public AuthModels.UserSummary updateAvatar(UUID userId, MultipartFile file) {
        UserAccount user = requireUser(userId);
        MediaStorageService.StoredImage stored = mediaStorage.storeCommunityImage(file);
        String previousAvatarUrl = user.getAvatarUrl();
        user.setAvatarUrl(stored.relativeUrl());
        user.setAvatarKey(null);
        AuthModels.UserSummary saved = summary(userRepository.save(user));
        deleteReplacedAvatar(previousAvatarUrl, user.getAvatarUrl());
        return saved;
    }

    /** 移除自定义头像，回到预设图案或默认图案。 */
    @Transactional
    public AuthModels.UserSummary removeAvatar(UUID userId) {
        UserAccount user = requireUser(userId);
        String previousAvatarUrl = user.getAvatarUrl();
        user.setAvatarUrl(null);
        AuthModels.UserSummary saved = summary(userRepository.save(user));
        deleteReplacedAvatar(previousAvatarUrl, null);
        return saved;
    }

    /**
     * 换头像后清掉旧文件。
     *
     * 只在旧地址确实指向本服务媒体库时才删 —— 地址不是本服务的（或已经是空）
     * 一律不碰，避免把别的资源删掉。
     */
    private void deleteReplacedAvatar(String previousUrl, String currentUrl) {
        if (previousUrl == null || previousUrl.isBlank() || previousUrl.equals(currentUrl)) {
            return;
        }
        String fileName = MediaStorageService.fileNameOf(previousUrl);
        if (fileName != null) {
            mediaStorage.delete(fileName);
        }
    }

    @Transactional
    public void changePassword(UUID userId, String currentPassword, String newPassword) {
        UserAccount user = requireUser(userId);
        if (!passwordEncoder.matches(currentPassword, user.getPasswordHash())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CURRENT_PASSWORD_INVALID", "当前密码不正确");
        }
        if (passwordEncoder.matches(newPassword, user.getPasswordHash())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PASSWORD_UNCHANGED", "新密码不能与当前密码相同");
        }
        user.setPasswordHash(passwordEncoder.encode(newPassword));
        userRepository.save(user);
        revokeAllRefreshTokens(userId);
    }

    @Transactional
    public void logoutAll(UUID userId) {
        requireUser(userId);
        revokeAllRefreshTokens(userId);
    }

    @Transactional
    public void deleteAccount(UUID userId, String password) {
        UserAccount user = requireUser(userId);
        if (!passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CURRENT_PASSWORD_INVALID", "密码不正确，无法删除账号");
        }
        accountDeletionService.delete(userId);
    }

    private UserAccount requireUser(UUID userId) {
        return userRepository.findById(userId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "登录状态已失效"));
    }

    private void revokeAllRefreshTokens(UUID userId) {
        Instant now = Instant.now();
        List<RefreshToken> tokens = refreshTokenRepository.findByUserIdAndRevokedFalse(userId);
        tokens.forEach(token -> {
            token.setRevoked(true);
            token.setRevokedAt(now);
        });
        refreshTokenRepository.saveAll(tokens);
    }

    private AuthModels.AuthResponse issueTokens(UserAccount user) {
        String accessToken = jwtService.createAccessToken(user.getId(), user.getUsername(), user.getRoles());
        String refreshToken = jwtService.createRefreshToken(user.getId());
        RefreshToken entity = new RefreshToken();
        entity.setUser(user);
        entity.setTokenHash(TokenHash.sha256Hex(refreshToken));
        entity.setExpiresAt(jwtService.refreshExpiresAt(refreshToken));
        refreshTokenRepository.save(entity);
        return new AuthModels.AuthResponse(accessToken, refreshToken, jwtService.accessTokenSeconds(), summary(user));
    }

    private AuthModels.UserSummary summary(UserAccount user) {
        return new AuthModels.UserSummary(user.getId(), user.getUsername(), user.getNickname(),
            user.getEmail(), user.getAvatarKey(), user.getAvatarUrl(),
            user.isEmailVerified(), Set.copyOf(user.getRoles()));
    }

    private Claims parseRefresh(String rawRefreshToken) {
        try {
            Claims claims = jwtService.parse(rawRefreshToken);
            if (!jwtService.isType(claims, "refresh")) {
                throw invalidRefreshToken();
            }
            return claims;
        } catch (ApiException exception) {
            throw exception;
        } catch (Exception exception) {
            throw invalidRefreshToken();
        }
    }

    private ApiException invalidCredentials() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_CREDENTIALS", "账号或密码不正确");
    }

    private ApiException invalidRefreshToken() {
        return new ApiException(HttpStatus.UNAUTHORIZED, "INVALID_REFRESH_TOKEN", "刷新令牌无效或已过期");
    }
}
