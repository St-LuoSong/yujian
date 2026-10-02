package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.UUID;

public final class FeedbackModels {
    private FeedbackModels() {
    }

    public record SubmitRequest(@NotBlank(message = "请填写反馈内容")
                                @Size(max = 1000, message = "反馈内容请控制在 1000 字以内") String content,
                                String category,
                                @Size(max = 160, message = "联系方式过长") String contact,
                                @Size(max = 120, message = "页面标识过长") String page) {
    }

    public record SubmitResult(UUID id, String status, Instant createdAt) {
    }

    public record FeedbackView(UUID id, String category, String content, String contact, String page,
                               String status, String handlerNote, boolean fromRegisteredUser,
                               Instant createdAt, Instant updatedAt) {
    }

    public record UpdateRequest(String status, @Size(max = 500, message = "处理说明过长") String handlerNote) {
    }
}
