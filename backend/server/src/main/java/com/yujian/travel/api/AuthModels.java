package com.yujian.travel.api;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.Set;
import java.util.UUID;

public final class AuthModels {
    private AuthModels() {
    }

    public record RegisterRequest(
        @NotBlank(message = "请输入用户名")
        @Size(min = 3, max = 32, message = "用户名长度应为3—32个字符")
        String username,
        @NotBlank(message = "请输入邮箱")
        @Email(message = "邮箱格式不正确")
        String email,
        @NotBlank(message = "请输入密码")
        @Size(min = 8, max = 72, message = "密码长度应为8—72个字符")
        String password) {
    }

    public record LoginRequest(
        @NotBlank(message = "请输入用户名或邮箱") String identifier,
        @NotBlank(message = "请输入密码") String password) {
    }

    public record RefreshRequest(@NotBlank(message = "刷新令牌不能为空") String refreshToken) {
    }

    public record LogoutRequest(String refreshToken) {
    }

    public record UserSummary(UUID id, String username, String nickname, String email,
                              String avatarKey, boolean emailVerified, Set<String> roles) {
    }

    public record AuthResponse(String accessToken, String refreshToken, long expiresIn, UserSummary user) {
    }

    public record UpdateProfileRequest(
        @Size(max = 40, message = "昵称不能超过 40 个字符") String nickname,
        @Size(max = 32, message = "头像标识不合法") String avatarKey) {
    }

    public record ChangePasswordRequest(
        @NotBlank(message = "请输入当前密码") String currentPassword,
        @NotBlank(message = "请输入新密码")
        @Size(min = 8, max = 72, message = "新密码长度应为8—72个字符")
        String newPassword) {
    }

    public record DeleteAccountRequest(@NotBlank(message = "请输入密码确认删除") String password) {
    }
}
