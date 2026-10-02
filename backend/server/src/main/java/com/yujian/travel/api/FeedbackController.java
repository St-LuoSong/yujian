package com.yujian.travel.api;

import com.yujian.travel.service.FeedbackService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 游客反馈入口。允许匿名提交：用户不必为了提一条意见先去注册。
 * 服务端只保存内容、可选联系方式与来源页面，不采集设备标识。
 */
@RestController
@RequestMapping("/api")
public class FeedbackController {
    private final FeedbackService feedbackService;

    public FeedbackController(FeedbackService feedbackService) {
        this.feedbackService = feedbackService;
    }

    @PostMapping("/feedback")
    @ResponseStatus(HttpStatus.CREATED)
    public FeedbackModels.SubmitResult submit(@Valid @RequestBody FeedbackModels.SubmitRequest request) {
        return feedbackService.submit(request);
    }
}
