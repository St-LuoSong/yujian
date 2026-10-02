package com.yujian.travel.api;

import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.CommunityService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/community")
public class CommunityController {
    private final CommunityService communityService;

    public CommunityController(CommunityService communityService) {
        this.communityService = communityService;
    }

    @GetMapping("/posts")
    public CommunityModels.PostPage feed(
        @RequestParam(required = false) String city,
        @RequestParam(required = false) String tag,
        @RequestParam(defaultValue = "1") int page,
        @RequestParam(defaultValue = "10") int size) {
        AuthUser viewer = CurrentUser.userOrNull();
        return communityService.feed(city, tag, page, size, viewer == null ? null : viewer.id());
    }

    @GetMapping("/posts/mine")
    public CommunityModels.PostPage mine(
        @RequestParam(defaultValue = "1") int page,
        @RequestParam(defaultValue = "10") int size) {
        return communityService.mine(CurrentUser.requireUser().id(), page, size);
    }

    @GetMapping("/posts/{id}")
    public CommunityModels.PostView detail(@PathVariable UUID id) {
        AuthUser viewer = CurrentUser.userOrNull();
        return communityService.detail(id, viewer == null ? null : viewer.id());
    }

    @PostMapping("/posts")
    @ResponseStatus(HttpStatus.CREATED)
    public CommunityModels.PostView create(@Valid @RequestBody CommunityModels.CreatePostRequest request) {
        return communityService.create(CurrentUser.requireUser().id(), request);
    }

    @PatchMapping("/posts/{id}")
    public CommunityModels.PostView update(@PathVariable UUID id,
                                           @Valid @RequestBody CommunityModels.UpdatePostRequest request) {
        return communityService.update(CurrentUser.requireUser().id(), id, request);
    }

    @DeleteMapping("/posts/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        communityService.delete(CurrentUser.requireUser().id(), id);
    }

    @PostMapping("/posts/{id}/like")
    public CommunityModels.PostView like(@PathVariable UUID id) {
        return communityService.like(CurrentUser.requireUser().id(), id);
    }

    @DeleteMapping("/posts/{id}/like")
    public CommunityModels.PostView unlike(@PathVariable UUID id) {
        return communityService.unlike(CurrentUser.requireUser().id(), id);
    }

    @PostMapping("/posts/{id}/report")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void report(@PathVariable UUID id,
                       @Valid @RequestBody CommunityModels.ReportRequest request) {
        communityService.report(CurrentUser.requireUser().id(), id, request.reason());
    }
}
