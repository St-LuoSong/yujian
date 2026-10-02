package com.yujian.travel.service;

import com.yujian.travel.api.FeedbackModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.Feedback;
import com.yujian.travel.repository.FeedbackRepository;
import com.yujian.travel.security.AnonymousPrincipal;
import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;

@Service
public class FeedbackService {
    private static final Set<String> CATEGORIES = Set.of("功能建议", "内容纠错", "数据问题", "其他");
    private static final Set<String> STATUSES = Set.of("OPEN", "HANDLED", "IGNORED");

    private final FeedbackRepository repository;

    public FeedbackService(FeedbackRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public FeedbackModels.SubmitResult submit(FeedbackModels.SubmitRequest request) {
        Feedback entity = new Feedback();
        AuthUser user = CurrentUser.userOrNull();
        AnonymousPrincipal anonymous = CurrentUser.anonymousOrNull();
        if (user != null) {
            entity.setUserId(user.id());
        }
        if (anonymous != null) {
            entity.setAnonymousSessionId(anonymous.sessionId());
        }
        entity.setCategory(normalizeCategory(request.category()));
        entity.setContent(request.content().trim());
        entity.setContact(blankToNull(request.contact()));
        entity.setPage(blankToNull(request.page()));
        entity.setStatus("OPEN");
        Feedback saved = repository.save(entity);
        return new FeedbackModels.SubmitResult(saved.getId(), saved.getStatus(), saved.getCreatedAt());
    }

    @Transactional(readOnly = true)
    public List<FeedbackModels.FeedbackView> list(String status) {
        List<Feedback> rows = status == null || status.isBlank()
            ? repository.findAllByOrderByCreatedAtDesc()
            : repository.findByStatusOrderByCreatedAtDesc(status.trim().toUpperCase(Locale.ROOT));
        return rows.stream().map(FeedbackService::toView).toList();
    }

    @Transactional
    public FeedbackModels.FeedbackView update(UUID id, FeedbackModels.UpdateRequest request) {
        Feedback entity = repository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "FEEDBACK_NOT_FOUND", "反馈不存在"));
        if (request.status() != null && !request.status().isBlank()) {
            String status = request.status().trim().toUpperCase(Locale.ROOT);
            if (!STATUSES.contains(status)) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "FEEDBACK_STATUS_INVALID", "反馈状态不合法");
            }
            entity.setStatus(status);
        }
        if (request.handlerNote() != null) {
            entity.setHandlerNote(blankToNull(request.handlerNote()));
        }
        return toView(repository.save(entity));
    }

    @Transactional(readOnly = true)
    public long countByStatus(String status) {
        return repository.countByStatus(status);
    }

    private static String normalizeCategory(String category) {
        if (category == null || category.isBlank()) {
            return "其他";
        }
        String trimmed = category.trim();
        return CATEGORIES.contains(trimmed) ? trimmed : "其他";
    }

    private static String blankToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static FeedbackModels.FeedbackView toView(Feedback entity) {
        return new FeedbackModels.FeedbackView(entity.getId(), entity.getCategory(), entity.getContent(),
            entity.getContact(), entity.getPage(), entity.getStatus(), entity.getHandlerNote(),
            entity.getUserId() != null, entity.getCreatedAt(), entity.getUpdatedAt());
    }
}
