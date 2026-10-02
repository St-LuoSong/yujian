package com.yujian.travel.service;

import com.yujian.travel.api.AuthModels;
import com.yujian.travel.domain.RefreshToken;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.RefreshTokenRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.security.JwtService;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.password.PasswordEncoder;

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
    private final AuthService service =
        new AuthService(users, refreshTokens, encoder, mock(JwtService.class), deletion);

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
