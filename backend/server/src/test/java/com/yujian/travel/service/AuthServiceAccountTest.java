package com.yujian.travel.service;

import com.yujian.travel.api.AuthModels;
import com.yujian.travel.domain.RefreshToken;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.RefreshTokenRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.security.JwtService;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthServiceAccountTest {
    private final UserAccountRepository users = mock(UserAccountRepository.class);
    private final RefreshTokenRepository refreshTokens = mock(RefreshTokenRepository.class);
    private final PasswordEncoder encoder = mock(PasswordEncoder.class);
    private final AccountDeletionService deletion = mock(AccountDeletionService.class);
    private final MediaStorageService mediaStorage = mock(MediaStorageService.class);
    private final AuthService service =
        new AuthService(users, refreshTokens, encoder, mock(JwtService.class), deletion, mediaStorage);

    @Test
    void profileUpdateKeepsNicknameAndPresetAvatar() {
        UUID userId = UUID.randomUUID();
        UserAccount user = user(userId, "old-hash");
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(users.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        AuthModels.UserSummary summary = service.updateProfile(userId, "  河洛旅人  ", "celadon");

        assertThat(summary.nickname()).isEqualTo("河洛旅人");
        assertThat(summary.avatarKey()).isEqualTo("celadon");
        assertThat(user.getNickname()).isEqualTo("河洛旅人");
    }

    @Test
    void passwordChangeRevokesRefreshTokens() {
        UUID userId = UUID.randomUUID();
        UserAccount user = user(userId, "old-hash");
        RefreshToken token = new RefreshToken();
        token.setUser(user);
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(encoder.matches("old-pass", "old-hash")).thenReturn(true);
        when(encoder.matches("new-pass-123", "old-hash")).thenReturn(false);
        when(encoder.encode("new-pass-123")).thenReturn("new-hash");
        when(refreshTokens.findByUserIdAndRevokedFalse(userId)).thenReturn(List.of(token));

        service.changePassword(userId, "old-pass", "new-pass-123");

        assertThat(user.getPasswordHash()).isEqualTo("new-hash");
        assertThat(token.isRevoked()).isTrue();
        verify(refreshTokens).saveAll(List.of(token));
    }

    @Test
    void accountDeletionRequiresPasswordAndDelegatesCascadeCleanup() {
        UUID userId = UUID.randomUUID();
        UserAccount user = user(userId, "hash");
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(encoder.matches("secret-123", "hash")).thenReturn(true);

        service.deleteAccount(userId, "secret-123");

        verify(deletion).delete(userId);
    }

    @Test
    void avatarUploadStoresTheRelativeUrlAndDropsThePresetKey() {
        UUID userId = UUID.randomUUID();
        UserAccount user = user(userId, "hash");
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(users.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));
        when(mediaStorage.storeCommunityImage(any()))
            .thenReturn(new MediaStorageService.StoredImage("avatar-1.jpg", "jpg", 2048L, 200, 200));

        AuthModels.UserSummary summary = service.updateAvatar(userId, mock(MultipartFile.class));

        // 存的是服务端相对路径：把上传时那个主机名写进库里，换域名之后所有历史头像都会失效。
        assertThat(summary.avatarUrl()).isEqualTo("/media/avatar-1.jpg");
        assertThat(summary.avatarKey()).isNull();
    }

    @Test
    void switchingToAPresetAvatarDeletesTheUploadedFile() {
        UUID userId = UUID.randomUUID();
        UserAccount user = user(userId, "hash");
        user.setAvatarUrl("/media/avatar-1.jpg");
        user.setAvatarKey(null);
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(users.save(any(UserAccount.class))).thenAnswer(invocation -> invocation.getArgument(0));

        AuthModels.UserSummary summary = service.updateProfile(userId, "河洛旅人", "kiln");

        assertThat(summary.avatarKey()).isEqualTo("kiln");
        assertThat(summary.avatarUrl()).isNull();
        // 换回预设图案后旧文件不该继续占着磁盘。
        verify(mediaStorage).delete("avatar-1.jpg");
    }

    private UserAccount user(UUID id, String passwordHash) {
        UserAccount user = new UserAccount();
        user.setId(id);
        user.setUsername("traveller");
        user.setEmail("traveller@example.com");
        user.setPasswordHash(passwordHash);
        user.setRoles(Set.of("USER"));
        return user;
    }
}
