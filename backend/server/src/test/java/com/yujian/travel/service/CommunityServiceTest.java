package com.yujian.travel.service;

import com.yujian.travel.api.CommunityModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.CommunityPostEntity;
import com.yujian.travel.domain.CommunityFavoriteEntity;
import com.yujian.travel.domain.CommunityCommentEntity;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.CommunityLikeRepository;
import com.yujian.travel.repository.CommunityFavoriteRepository;
import com.yujian.travel.repository.CommunityCommentRepository;
import com.yujian.travel.repository.CommunityCommentLikeRepository;
import com.yujian.travel.repository.CommunityPostRepository;
import com.yujian.travel.repository.CommunityReportRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class CommunityServiceTest {
    private final CommunityPostRepository posts = mock(CommunityPostRepository.class);
    private final CommunityLikeRepository likes = mock(CommunityLikeRepository.class);
    private final CommunityFavoriteRepository favorites = mock(CommunityFavoriteRepository.class);
    private final CommunityCommentRepository comments = mock(CommunityCommentRepository.class);
    private final CommunityCommentLikeRepository commentLikes =
        mock(CommunityCommentLikeRepository.class);
    private final CommunityReportRepository reports = mock(CommunityReportRepository.class);
    private final UserAccountRepository users = mock(UserAccountRepository.class);
    private final TripPlanRepository trips = mock(TripPlanRepository.class);
    private final MessageCenterService messageCenter = mock(MessageCenterService.class);
    private final MediaStorageService mediaStorage = mock(MediaStorageService.class);
    private final CommunityService service =
        new CommunityService(posts, likes, favorites, comments, commentLikes, reports, users, trips,
            messageCenter, mediaStorage);

    @Test
    void favoriteIsIdempotentAndKeepsItsOwnCount() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(UUID.randomUUID()));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(users.findById(userId)).thenReturn(Optional.of(user(userId)));
        when(favorites.existsByUserIdAndPostId(userId, postId)).thenReturn(false);
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.favorite(userId, postId);

        assertThat(post.getFavoriteCount()).isEqualTo(1);
        // 收藏不影响点赞计数，两者是独立的两个动作。
        assertThat(post.getLikeCount()).isZero();
        verify(favorites).save(any());
    }

    @Test
    void unfavoriteRemovesTheBookmarkAndDecrementsCount() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(UUID.randomUUID()));
        post.setFavoriteCount(1);
        CommunityFavoriteEntity existing = new CommunityFavoriteEntity();
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(favorites.findByUserIdAndPostId(userId, postId)).thenReturn(Optional.of(existing));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.unfavorite(userId, postId);

        assertThat(post.getFavoriteCount()).isZero();
        verify(favorites).delete(existing);
    }

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
        verify(messageCenter).publish(
            post.getUser().getId(), "COMMUNITY_MODERATION", "旅记",
            "你的旅记已通过审核", "《测试旅记》已通过审核，现在可以在旅记信息流中公开查看。");
    }

    @Test
    void moderationRejectionCreatesAnInboxMessageWithTheReviewNote() {
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(UUID.randomUUID()));
        post.setStatus(CommunityService.PENDING);
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.moderate(postId, CommunityService.REJECTED, "请补充图片来源");

        verify(messageCenter).publish(
            post.getUser().getId(), "COMMUNITY_MODERATION", "旅记",
            "你的旅记未通过审核", "《测试旅记》暂未通过审核。审核说明：请补充图片来源");
    }

    @Test
    void deletingAPostRemovesItsImagesWhenNothingElseUsesThem() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(userId));
        post.setImageUrls(new ArrayList<>(List.of("/media/a.jpg", "/media/b.jpg")));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(posts.countOthersUsingImageFile(any(), any())).thenReturn(0L);

        service.delete(userId, postId);

        verify(posts).delete(post);
        verify(mediaStorage).delete("a.jpg");
        verify(mediaStorage).delete("b.jpg");
    }

    @Test
    void deletingAPostKeepsImagesThatAnotherPostStillUses() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(userId));
        post.setImageUrls(new ArrayList<>(List.of("/media/shared.jpg")));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(posts.countOthersUsingImageFile(any(), any())).thenReturn(1L);

        service.delete(userId, postId);

        verify(posts).delete(post);
        verify(mediaStorage, never()).delete(any());
    }

    @Test
    void editingAPostRemovesOnlyTheDroppedImages() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(userId));
        post.setImageUrls(new ArrayList<>(List.of("/media/keep.jpg", "/media/drop.jpg")));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        when(posts.countOthersUsingImageFile(any(), any())).thenReturn(0L);

        service.update(userId, postId, new CommunityModels.UpdatePostRequest(
            "测试旅记", "测试内容", "洛阳", "历史文化", "PUBLIC", null,
            List.of("/media/keep.jpg")));

        verify(mediaStorage, never()).delete("keep.jpg");
        verify(mediaStorage).delete("drop.jpg");
    }

    @Test
    void commentingCountsOnceAndTellsTheAuthor() {
        UUID authorId = UUID.randomUUID();
        UUID commenterId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(authorId));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(users.findById(commenterId)).thenReturn(Optional.of(user(commenterId)));
        when(comments.save(any(CommunityCommentEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        CommunityModels.CommentView view =
            service.addComment(commenterId, postId, "  龙门石窟值得一去  ", null);

        assertThat(post.getCommentCount()).isEqualTo(1);
        // 首尾空白在服务端就裁掉，不让"看起来空"的评论进库。
        assertThat(view.content()).isEqualTo("龙门石窟值得一去");
        verify(messageCenter).publish(eq(authorId), eq("COMMUNITY_COMMENT"), any(), any(), any());
    }

    @Test
    void commentingYourOwnPostDoesNotRaiseANotification() {
        UUID authorId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(authorId));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(users.findById(authorId)).thenReturn(Optional.of(user(authorId)));
        when(comments.save(any(CommunityCommentEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.addComment(authorId, postId, "记录一下", null);

        assertThat(post.getCommentCount()).isEqualTo(1);
        verifyNoInteractions(messageCenter);
    }

    @Test
    void deletingAPostRemovesItsComments() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(userId));
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));

        service.delete(userId, postId);

        // 评论表有指向旅记的外键：漏掉这一步，线上会直接抛约束冲突。
        verify(comments).deleteByPostId(postId);
        verify(posts).delete(post);
    }

    @Test
    void replyingToAReplyStaysUnderTheSameRootComment() {
        UUID commenterId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        UUID authorId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(authorId));
        CommunityCommentEntity root = comment(UUID.randomUUID(), post, user(authorId), null);
        CommunityCommentEntity firstReply =
            comment(UUID.randomUUID(), post, user(authorId), root.getId());
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(users.findById(commenterId)).thenReturn(Optional.of(user(commenterId)));
        when(comments.findById(firstReply.getId())).thenReturn(Optional.of(firstReply));
        // 收敛到顶层评论时还会再查一次它的父级。
        when(comments.findById(root.getId())).thenReturn(Optional.of(root));
        when(comments.save(any(CommunityCommentEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        when(posts.save(any(CommunityPostEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        CommunityModels.CommentView view =
            service.addComment(commenterId, postId, "同问", firstReply.getId());

        // 回复的回复收敛到同一条顶层评论：树永远只有两层，客户端不用递归渲染。
        assertThat(view.parentId()).isEqualTo(root.getId());
        assertThat(post.getCommentCount()).isEqualTo(1);
    }

    @Test
    void likingACommentTwiceCountsOnce() {
        UUID userId = UUID.randomUUID();
        UUID postId = UUID.randomUUID();
        CommunityPostEntity post = publicPost(postId, user(UUID.randomUUID()));
        CommunityCommentEntity target =
            comment(UUID.randomUUID(), post, user(UUID.randomUUID()), null);
        when(posts.findWithDetailsById(postId)).thenReturn(Optional.of(post));
        when(comments.findById(target.getId())).thenReturn(Optional.of(target));
        when(users.findById(userId)).thenReturn(Optional.of(user(userId)));
        when(commentLikes.existsByUserIdAndCommentId(userId, target.getId()))
            .thenReturn(false, true);
        when(comments.save(any(CommunityCommentEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        service.likeComment(userId, target.getId());
        service.likeComment(userId, target.getId());

        assertThat(target.getLikeCount()).isEqualTo(1);
        verify(commentLikes).save(any());
    }

    private CommunityCommentEntity comment(UUID id, CommunityPostEntity post,
                                           UserAccount author, UUID parentId) {
        CommunityCommentEntity comment = new CommunityCommentEntity();
        comment.setId(id);
        comment.setPost(post);
        comment.setUser(author);
        comment.setContent("内容");
        comment.setParentId(parentId);
        comment.setStatus(CommunityCommentEntity.ACTIVE);
        return comment;
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
