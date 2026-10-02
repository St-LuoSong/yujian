package com.yujian.travel.service;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.domain.UserMessageEntity;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.repository.UserMessageRepository;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 服务端消息中心。
 *
 * 首次读取时为账号种入一组产品与数据说明；之后已读状态跟账号走，不再随进程重启丢失。
 */
@Service
public class MessageCenterService {
    private final UserMessageRepository messages;
    private final UserAccountRepository users;

    public MessageCenterService(UserMessageRepository messages, UserAccountRepository users) {
        this.messages = messages;
        this.users = users;
    }

    @Transactional
    public InboxView inbox(UUID userId) {
        seedIfEmpty(userId);
        List<MessageView> items = messages.findByUserIdOrderByCreatedAtDesc(userId).stream()
            .map(this::view)
            .toList();
        return new InboxView(items, messages.countByUserIdAndReadFalse(userId));
    }

    public long unreadCount(UUID userId) {
        return messages.countByUserIdAndReadFalse(userId);
    }

    @Transactional
    public MessageView markRead(UUID userId, UUID messageId) {
        UserMessageEntity message = messages.findByIdAndUserId(messageId, userId)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MESSAGE_NOT_FOUND", "消息不存在"));
        if (!message.isRead()) {
            message.setRead(true);
            message.setReadAt(Instant.now());
            message = messages.save(message);
        }
        return view(message);
    }

    @Transactional
    public int markAllRead(UUID userId) {
        List<UserMessageEntity> unread = messages.findByUserIdAndReadFalse(userId);
        Instant now = Instant.now();
        unread.forEach(item -> {
            item.setRead(true);
            item.setReadAt(now);
        });
        messages.saveAll(unread);
        return unread.size();
    }

    private void seedIfEmpty(UUID userId) {
        if (messages.existsByUserId(userId)) {
            return;
        }
        UserAccount user = users.findById(userId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "登录状态已失效"));
        messages.saveAll(List.of(
            message(user, "RELEASE", "版本", "行程页新增「你的足迹」",
                "足迹里的城市、里程与旅行天数都由已保存的行程聚合；里程只统计路线工具真的给过距离的路段。"),
            message(user, "DATA", "数据", "天气、车次与路线从哪里来",
                "外部数据统一由服务端调用，并在行程里标注实时、缓存、系统资料或演示数据。"),
            message(user, "PRIVACY", "安全", "我们不采集这些信息",
                "身份证号、银行卡号、支付信息与后台持续定位都不在采集范围内；定位只在你主动打开附近景点时请求一次。"),
            message(user, "TRIP_SYNC", "行程", "保存的行程跟着账号走",
                "登录后同一份行程可以在其它设备打开；分享出去的是只读链接，对方改不到原方案。")
        ));
    }

    private UserMessageEntity message(UserAccount user, String type, String tag,
                                      String title, String body) {
        UserMessageEntity message = new UserMessageEntity();
        message.setUser(user);
        message.setType(type);
        message.setTitle(title);
        message.setBody(body);
        message.setRead(false);
        return message;
    }

    private MessageView view(UserMessageEntity message) {
        return new MessageView(message.getId(), message.getType(), message.getTitle(),
            message.getBody(), message.isRead(), message.getCreatedAt(), message.getReadAt());
    }

    public record InboxView(List<MessageView> items, long unread) {
    }

    public record MessageView(UUID id, String type, String title, String body,
                              boolean read, Instant createdAt, Instant readAt) {
    }
}
