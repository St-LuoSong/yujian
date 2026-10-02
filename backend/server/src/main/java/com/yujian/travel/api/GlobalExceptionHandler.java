package com.yujian.travel.api;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.time.Instant;

@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiError> handleApiException(ApiException exception) {
        return ResponseEntity.status(exception.getStatus())
            .body(new ApiError(exception.getCode(), exception.getMessage(), Instant.now()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> handleValidation(MethodArgumentNotValidException exception) {
        String message = exception.getBindingResult().getFieldErrors().stream()
            .findFirst()
            .map(error -> error.getDefaultMessage() == null ? "请求参数不合法" : error.getDefaultMessage())
            .orElse("请求参数不合法");
        return ResponseEntity.badRequest().body(new ApiError("VALIDATION_ERROR", message, Instant.now()));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ApiError> handleConstraintViolation(ConstraintViolationException exception) {
        return ResponseEntity.badRequest().body(new ApiError("VALIDATION_ERROR", exception.getMessage(), Instant.now()));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiError> handleAccessDenied(AccessDeniedException exception) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
            .body(new ApiError("ACCESS_DENIED", "当前账号无权执行该操作", Instant.now()));
    }

    /**
     * 外部数据源失败（百度地图、天气、12306）。
     *
     * 这类失败不是"服务器崩了"，而是一条可解释的依赖不可用：
     * 用 503 与稳定的错误码回答，客户端可以据此提示"稍后再试"，
     * 运营统计也能把它与真正的内部错误区分开。
     */
    @ExceptionHandler(ExternalServiceException.class)
    public ResponseEntity<ApiError> handleExternal(ExternalServiceException exception) {
        log.warn("外部数据源不可用：{} {}", exception.getCode(), exception.getMessage());
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
            .body(new ApiError(exception.getCode(), exception.getMessage(), Instant.now()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> handleUnexpected(Exception exception) {
        log.error("未处理的系统异常", exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ApiError("INTERNAL_ERROR", "系统暂时无法处理请求，请稍后再试", Instant.now()));
    }

    public record ApiError(String code, String message, Instant timestamp) {
    }
}
