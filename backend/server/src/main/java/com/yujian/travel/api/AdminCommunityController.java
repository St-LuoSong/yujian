package com.yujian.travel.api;

import com.yujian.travel.service.CommunityService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/admin/community")
public class AdminCommunityController {
    private final CommunityService communityService;
    private final OperationLogService operationLog;

    public AdminCommunityController(CommunityService communityService, OperationLogService operationLog) {
        this.communityService = communityService;
        this.operationLog = operationLog;
    }

    @GetMapping("/posts")
    public CommunityModels.PostPage posts(
        @RequestParam(defaultValue = "PENDING") String status,
        @RequestParam(defaultValue = "1") int page,
        @RequestParam(defaultValue = "10") int size) {
        return communityService.moderationList(status, page, size);
    }

    @PatchMapping("/posts/{id}/status")
    public CommunityModels.PostView moderate(@PathVariable UUID id,
                                             @Valid @RequestBody CommunityModels.ModerationRequest request) {
        CommunityModels.PostView result = communityService.moderate(id, request.status(), request.note());
        operationLog.record("COMMUNITY_POST_MODERATE", id.toString(),
            "社区旅记审核为：" + result.status());
        return result;
    }

    @GetMapping("/reports")
    public CommunityModels.ReportPage reports(
        @RequestParam(defaultValue = "OPEN") String status,
        @RequestParam(defaultValue = "1") int page,
        @RequestParam(defaultValue = "10") int size) {
        return communityService.reports(status, page, size);
    }

    @PatchMapping("/reports/{id}")
    public CommunityModels.ReportView handleReport(
        @PathVariable UUID id,
        @Valid @RequestBody CommunityModels.ReportHandleRequest request) {
        CommunityModels.ReportView result = communityService.handleReport(id, request.status(), request.note());
        operationLog.record("COMMUNITY_REPORT_HANDLE", id.toString(),
            "社区举报处理为：" + result.status());
        return result;
    }

    /** 一篇旅记下的全部评论，含已隐藏的。 */
    @GetMapping("/posts/{id}/comments")
    public CommunityModels.CommentPage comments(
        @PathVariable UUID id,
        @RequestParam(defaultValue = "1") int page,
        @RequestParam(defaultValue = "50") int size) {
        return communityService.allComments(id, page, size);
    }

    @PatchMapping("/comments/{id}")
    public CommunityModels.CommentView moderateComment(
        @PathVariable UUID id,
        @Valid @RequestBody CommunityModels.CommentModerationRequest request) {
        CommunityModels.CommentView result = communityService.moderateComment(id, request.status());
        operationLog.record("COMMUNITY_COMMENT_MODERATE", id.toString(),
            "社区评论处理为：" + request.status());
        return result;
    }
}
