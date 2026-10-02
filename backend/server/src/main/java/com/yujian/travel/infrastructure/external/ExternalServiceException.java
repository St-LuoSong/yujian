package com.yujian.travel.infrastructure.external;

/**
 * 外部服务调用失败。
 *
 * message 里刻意不携带完整请求地址，避免把 API Key 写进日志或用户可见提示。
 */
public class ExternalServiceException extends RuntimeException {
    private final String code;

    public ExternalServiceException(String code, String message) {
        super(message);
        this.code = code;
    }

    public ExternalServiceException(String code, String message, Throwable cause) {
        super(message, cause);
        this.code = code;
    }

    public String getCode() {
        return code;
    }
}
