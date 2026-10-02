package com.yujian.travel.api;

import com.yujian.travel.service.FeedbackService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/admin/feedback")
public class AdminFeedbackController {
    private final FeedbackService feedbackService;
    private final OperationLogService operationLog;

    public AdminFeedbackController(FeedbackService feedbackService, OperationLogService operationLog) {
        this.feedbackService = feedbackService;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<FeedbackModels.FeedbackView> list(@RequestParam(required = false) String status) {
        return feedbackService.list(status);
    }

    @PatchMapping("/{id}")
    public FeedbackModels.FeedbackView update(@PathVariable UUID id,
                                              @Valid @RequestBody FeedbackModels.UpdateRequest request) {
        FeedbackModels.FeedbackView updated = feedbackService.update(id, request);
        operationLog.record("FEEDBACK_UPDATE", "feedback:" + id, updated.status());
        return updated;
    }
}
