package com.yujian.travel.service;

import com.yujian.travel.api.CommunityModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.CommunityPostEntity;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.CommunityLikeRepository;
import com.yujian.travel.repository.CommunityPostRepository;
import com.yujian.travel.repository.CommunityReportRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.junit.jupiter.api.Test;

import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class CommunityServiceTest {
    private final CommunityPostRepository posts = mock(CommunityPostRepository.class);
    private final CommunityLikeRepository likes = mock(CommunityLikeRepository.class);
    private final CommunityReportRepository reports = mock(CommunityReportRepository.class);
    private final UserAccountRepository users = mock(UserAccountRepository.class);
    private final TripPlanRepository trips = mock(TripPlanRepository.class);
    private final CommunityService service =
        new CommunityService(posts, likes, reports, users, trips);

    @Test
    void createAlwaysStartsPendingAndRequiresExplicitVisibility() {
        UUID userId = UUID.randomUUID();
        when(users.findById(userId)).thenReturn(Optional.of(user(userId)));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        CommunityModels.PostView created = service.create(userId,
            new CommunityModels.CreatePostRequest("洛阳两日", "沿着伊河看石窟。", "洛阳",
                "历史文化", "PUBLIC", null, null));

        assertThat(created.status()).isEqualTo(CommunityService.PENDING);
        assertThat(created.visibility()).isEqualTo(CommunityService.PUBLIC);
        assertThat(created.title()).isEqualTo("洛阳两日");
    }

    @Test
    void likeIsIdempotentAndUpdatesCountOnlyOnce() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        UserAccount author = user(UUID.randomUUID());
        CommunityPostEntity post = publicPost(postId, author);
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(users.findById(userId)).thenReturn(Optional.of(user(userId)));
        when(likes.existsByUserIdAndPostId(userId, postId)).thenReturn(false);
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.like(userId, postId);

        assertThat(post.getLikeCount()).isEqualTo(1);
        verify(likes).save(any());
    }

    @Test
    void reportRejectsAuthorReportingOwnPost() {
        UUID authorId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(authorId));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));

        assertThatThrownBy(() -> service.report(authorId, postId, "测试举报"))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("不能举报自己的旅记");
    }

    @Test
    void moderationPublishesApprovedPost() {
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(UUID.randomUUID()));
        post.setStatus(CommunityService.PENDING);
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        CommunityModels.PostView view = service.moderate(postId, CommunityService.APPROVED, "内容合规");

        assertThat(view.status()).isEqualTo(CommunityService.APPROVED);
        assertThat(view.publishedAt()).isNotNull();
    }

    private CommunityPostEntity publicPost(UUID postId, UserAccount author) {
        CommunityPostEntity post = new CommunityPostEntity();
        post.setId(postId);
        post.setUser(author);
        post.setTitle("测试旅记");
        post.setContent("测试内容");
        post.setCity("洛阳");
        post.setVisibility(CommunityService.PUBLIC);
        post.setStatus(CommunityService.APPROVED);
        return post;
    }

    private UserAccount user(UUID id) {
        UserAccount user = new UserAccount();
        user.setId(id);
        user.setUsername("traveller");
        user.setNickname("河洛旅人");
        user.setEmail("traveller@example.test");
        user.setPasswordHash("hash");
        return user;
    }
}
