package com.yujian.travel.service;

import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.domain.UserMessageEntity;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.repository.UserMessageRepository;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class MessageCenterServiceTest {
    private final UserMessageRepository messages = mock(UserMessageRepository.class);
    private final UserAccountRepository users = mock(UserAccountRepository.class);
    private final MessageCenterService service = new MessageCenterService(messages, users);

    @Test
    void firstInboxSeedsDefaultsForTheAccount() {
        UUID userId = UUID.randomUUID();
        UserAccount user = new UserAccount();
        user.setId(userId);
        UserMessageEntity first = message(user);
        when(messages.existsByUserId(userId)).thenReturn(false);
        when(users.findById(userId)).thenReturn(Optional.of(user));
        when(messages.findByUserIdOrderByCreatedAtDesc(userId)).thenReturn(List.of(first));
        when(messages.countByUserIdAndReadFalse(userId)).thenReturn(1L);

        MessageCenterService.InboxView inbox = service.inbox(userId);

        assertThat(inbox.items()).hasSize(1);
        assertThat(inbox.unread()).isEqualTo(1);
        verify(messages).saveAll(any());
    }

    @Test
    void markAllReadReturnsNumberOfUpdatedMessages() {
        UUID userId = UUID.randomUUID();
        UserMessageEntity first = message(new UserAccount());
        UserMessageEntity second = message(new UserAccount());
        when(messages.findByUserIdAndReadFalse(userId)).thenReturn(List.of(first, second));

        int updated = service.markAllRead(userId);

        assertThat(updated).isEqualTo(2);
        assertThat(first.isRead()).isTrue();
        assertThat(second.isRead()).isTrue();
        verify(messages).saveAll(List.of(first, second));
    }

    private UserMessageEntity message(UserAccount user) {
        UserMessageEntity message = new UserMessageEntity();
        message.setUser(user);
        message.setType("SYSTEM");
        message.setTitle("测试消息");
        message.setBody("测试内容");
        message.setRead(false);
        return message;
    }
}
