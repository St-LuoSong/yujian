package com.yujian.travel.service;

import com.yujian.travel.api.EmailModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.EmailVerification;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.EmailVerificationRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.security.TokenHash;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.core.env.Environment;
import org.springframework.http.HttpStatus;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Locale;

@Service
public class EmailVerificationService {
    private static final Logger log = LoggerFactory.getLogger(EmailVerificationService.class);
    private static final SecureRandom RANDOM = new SecureRandom();

    private final EmailVerificationRepository verificationRepository;
    private final UserAccountRepository userRepository;
    private final ObjectProvider<JavaMailSender> mailSenderProvider;
    private final AppProperties properties;
    private final Environment environment;

    public EmailVerificationService(EmailVerificationRepository verificationRepository,
                                    UserAccountRepository userRepository,
                                    ObjectProvider<JavaMailSender> mailSenderProvider,
                                    AppProperties properties,
                                    Environment environment) {
        this.verificationRepository = verificationRepository;
        this.userRepository = userRepository;
        this.mailSenderProvider = mailSenderProvider;
        this.properties = properties;
        this.environment = environment;
    }

    @Transactional
    public EmailModels.MessageResponse sendCode(String rawEmail, String rawPurpose) {
        String email = normalizeEmail(rawEmail);
        String purpose = normalizePurpose(rawPurpose);
        verificationRepository.findTopByEmailAndPurposeOrderByCreatedAtDesc(email, purpose).ifPresent(last -> {
            if (last.getCreatedAt().plusSeconds(properties.getSmtp().getResendSeconds()).isAfter(Instant.now())) {
                throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "CODE_RATE_LIMITED",
                    "验证码发送过于频繁，请稍后再试");
            }
        });

        String code = String.format(Locale.ROOT, "%06d", RANDOM.nextInt(1_000_000));
        EmailVerification verification = new EmailVerification();
        verification.setEmail(email);
        verification.setPurpose(purpose);
        verification.setCodeHash(TokenHash.sha256Hex(code));
        verification.setExpiresAt(Instant.now().plus(properties.getSmtp().getCodeMinutes(), ChronoUnit.MINUTES));
        verificationRepository.save(verification);

        boolean sent = sendMail(email, code, purpose);
        boolean production = environment.acceptsProfiles(org.springframework.core.env.Profiles.of("prod"));
        String debugCode = !sent && !production && properties.getSmtp().isMockCodeLog() ? code : null;
        return new EmailModels.MessageResponse("验证码已发送，请查收邮箱", debugCode);
    }

    @Transactional
    public EmailModels.MessageResponse verifyCode(String rawEmail, String rawCode, String rawPurpose) {
        String email = normalizeEmail(rawEmail);
        String purpose = normalizePurpose(rawPurpose);
        EmailVerification verification = verificationRepository
            .findTopByEmailAndPurposeOrderByCreatedAtDesc(email, purpose)
            .orElseThrow(this::invalidCode);
        if (verification.getConsumedAt() != null || verification.getExpiresAt().isBefore(Instant.now())) {
            throw invalidCode();
        }
        if (verification.getAttempts() >= properties.getSmtp().getMaxAttempts()) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "CODE_ATTEMPTS_EXCEEDED",
                "验证码尝试次数过多，请重新获取");
        }
        if (!verification.getCodeHash().equals(TokenHash.sha256Hex(rawCode.trim()))) {
            verification.setAttempts(verification.getAttempts() + 1);
            throw invalidCode();
        }
        verification.setConsumedAt(Instant.now());
        userRepository.findByEmailIgnoreCase(email).ifPresent(user -> user.setEmailVerified(true));
        return new EmailModels.MessageResponse("邮箱验证成功", null);
    }

    private boolean sendMail(String email, String code, String purpose) {
        if (!properties.getSmtp().isEnabled()) {
            if (properties.getSmtp().isMockCodeLog()) {
                log.info("SMTP 未启用，{} 验证码（{}）已生成: {}", email, purpose, code);
            }
            return false;
        }
        JavaMailSender sender = mailSenderProvider.getIfAvailable();
        if (sender == null) {
            return false;
        }
        SimpleMailMessage message = new SimpleMailMessage();
        message.setFrom(properties.getSmtp().getFrom());
        message.setTo(email);
        message.setSubject("豫见智旅邮箱验证码");
        message.setText("你的验证码是 " + code + "，"
            + properties.getSmtp().getCodeMinutes() + " 分钟内有效。请勿将验证码转发给他人。");
        sender.send(message);
        return true;
    }

    private String normalizeEmail(String email) {
        return email == null ? "" : email.trim().toLowerCase(Locale.ROOT);
    }

    private String normalizePurpose(String purpose) {
        if (purpose == null || purpose.isBlank()) {
            return "VERIFY_EMAIL";
        }
        return purpose.trim().toUpperCase(Locale.ROOT);
    }

    private ApiException invalidCode() {
        return new ApiException(HttpStatus.BAD_REQUEST, "CODE_INVALID", "验证码不正确或已失效");
    }
}
