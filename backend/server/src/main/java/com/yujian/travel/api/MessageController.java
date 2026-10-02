package com.yujian.travel.api;

import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.MessageCenterService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/messages")
public class MessageController {
    private final MessageCenterService messageCenterService;

    public MessageController(MessageCenterService messageCenterService) {
        this.messageCenterService = messageCenterService;
    }

    @GetMapping
    public MessageCenterService.InboxView inbox() {
        return messageCenterService.inbox(CurrentUser.requireUser().id());
    }

    @GetMapping("/unread-count")
    public Map<String, Long> unreadCount() {
        return Map.of("unread", messageCenterService.unreadCount(CurrentUser.requireUser().id()));
    }

    @PatchMapping("/{id}/read")
    public MessageCenterService.MessageView markRead(@PathVariable UUID id) {
        return messageCenterService.markRead(CurrentUser.requireUser().id(), id);
    }

    @PatchMapping("/read-all")
    public Map<String, Object> markAllRead() {
        int updated = messageCenterService.markAllRead(CurrentUser.requireUser().id());
        return Map.of("updated", updated, "unread", 0);
    }
}
