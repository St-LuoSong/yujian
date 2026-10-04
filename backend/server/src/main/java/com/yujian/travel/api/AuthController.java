package com.yujian.travel.api;

import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.AccountMergeService;
import com.yujian.travel.service.AnonymousSessionService;
import com.yujian.travel.service.AuthService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthService authService;
    private final AnonymousSessionService anonymousSessionService;
    private final AccountMergeService accountMergeService;

    public AuthController(AuthService authService, AnonymousSessionService anonymousSessionService,
                          AccountMergeService accountMergeService) {
        this.authService = authService;
        this.anonymousSessionService = anonymousSessionService;
        this.accountMergeService = accountMergeService;
    }

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthModels.AuthResponse register(@Valid @RequestBody AuthModels.RegisterRequest request) {
        return authService.register(request);
    }

    @PostMapping("/login")
    public AuthModels.AuthResponse login(@Valid @RequestBody AuthModels.LoginRequest request) {
        return authService.login(request);
    }

    @PostMapping("/refresh")
    public AuthModels.AuthResponse refresh(@Valid @RequestBody AuthModels.RefreshRequest request) {
        return authService.refresh(request.refreshToken());
    }

    @PostMapping("/logout")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@RequestBody(required = false) AuthModels.LogoutRequest request) {
        authService.logout(request == null ? null : request.refreshToken());
    }

    @GetMapping("/me")
    public AuthModels.UserSummary me() {
        return authService.me(CurrentUser.requireUser().id());
    }

    @PatchMapping("/me")
    public AuthModels.UserSummary updateMe(@Valid @RequestBody AuthModels.UpdateProfileRequest request) {
        return authService.updateProfile(CurrentUser.requireUser().id(), request.nickname(), request.avatarKey());
    }

    /** 自定义头像上传。与旅记图片共用同一条重编码去 EXIF 的存储链路。 */
    @PostMapping(value = "/me/avatar", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public AuthModels.UserSummary uploadAvatar(@RequestParam("file") MultipartFile file) {
        return authService.updateAvatar(CurrentUser.requireUser().id(), file);
    }

    @DeleteMapping("/me/avatar")
    public AuthModels.UserSummary removeAvatar() {
        return authService.removeAvatar(CurrentUser.requireUser().id());
    }

    @PostMapping("/change-password")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void changePassword(@Valid @RequestBody AuthModels.ChangePasswordRequest request) {
        authService.changePassword(CurrentUser.requireUser().id(), request.currentPassword(), request.newPassword());
    }

    @PostMapping("/logout-all")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void logoutAll() {
        authService.logoutAll(CurrentUser.requireUser().id());
    }

    @DeleteMapping("/me")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteAccount(@Valid @RequestBody AuthModels.DeleteAccountRequest request) {
        authService.deleteAccount(CurrentUser.requireUser().id(), request.password());
    }

    @PostMapping("/merge-anonymous")
    public Map<String, Object> mergeAnonymous(
        @RequestHeader(value = "X-Anonymous-Token", required = false) String anonymousToken) {
        var user = CurrentUser.requireUser();
        var anonymousSessionId = anonymousSessionService.requireSessionIdByToken(anonymousToken);
        accountMergeService.merge(anonymousSessionId, user.id());
        return Map.of("merged", true, "userId", user.id().toString());
    }
}
