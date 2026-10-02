package com.yujian.travel.api;

import com.yujian.travel.service.EmailVerificationService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/email")
public class EmailController {
    private final EmailVerificationService emailVerificationService;

    public EmailController(EmailVerificationService emailVerificationService) {
        this.emailVerificationService = emailVerificationService;
    }

    @PostMapping("/send-code")
    public EmailModels.MessageResponse sendCode(@Valid @RequestBody EmailModels.SendCodeRequest request) {
        return emailVerificationService.sendCode(request.email(), request.purpose());
    }

    @PostMapping("/verify-code")
    public EmailModels.MessageResponse verifyCode(@Valid @RequestBody EmailModels.VerifyCodeRequest request) {
        return emailVerificationService.verifyCode(request.email(), request.code(), request.purpose());
    }
}
