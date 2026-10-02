package com.yujian.travel.api;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public final class EmailModels {
    private EmailModels() {
    }

    public record SendCodeRequest(
        @NotBlank(message = "请输入邮箱")
        @Email(message = "邮箱格式不正确") String email,
        String purpose) {
    }

    public record VerifyCodeRequest(
        @NotBlank(message = "请输入邮箱")
        @Email(message = "邮箱格式不正确") String email,
        @NotBlank(message = "请输入验证码") String code,
        String purpose) {
    }

    public record MessageResponse(String message, String debugCode) {
    }
}
