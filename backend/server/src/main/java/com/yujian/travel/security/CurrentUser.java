package com.yujian.travel.security;

import com.yujian.travel.common.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;

public final class CurrentUser {
    private CurrentUser() {
    }

    public static AuthUser requireUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.getPrincipal() instanceof AuthUser user) {
            return user;
        }
        throw new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "请先登录后继续操作");
    }

    public static AnonymousPrincipal anonymousOrNull() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.getPrincipal() instanceof AnonymousPrincipal principal) {
            return principal;
        }
        return null;
    }

    public static AuthUser userOrNull() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.getPrincipal() instanceof AuthUser user) {
            return user;
        }
        return null;
    }
}
