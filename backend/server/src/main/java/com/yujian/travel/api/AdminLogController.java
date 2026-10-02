package com.yujian.travel.api;

import com.yujian.travel.domain.OperationLog;
import com.yujian.travel.repository.OperationLogRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/admin/logs")
public class AdminLogController {
    private static final int MAX_LIMIT = 200;

    private final OperationLogRepository repository;

    public AdminLogController(OperationLogRepository repository) {
        this.repository = repository;
    }

    @GetMapping
    public List<OperationLog> list(@RequestParam(defaultValue = "50") int limit) {
        int size = Math.max(1, Math.min(MAX_LIMIT, limit));
        return repository.findAllByOrderByCreatedAtDesc(PageRequest.of(0, size));
    }
}
