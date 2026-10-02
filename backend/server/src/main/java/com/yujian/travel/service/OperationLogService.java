package com.yujian.travel.service;

import com.yujian.travel.domain.OperationLog;
import com.yujian.travel.repository.OperationLogRepository;
import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 写入管理员操作日志。
 *
 * 用 REQUIRES_NEW 是为了让日志在主操作回滚时依然保留失败痕迹；
 * detail 只保存人可读摘要，绝不写入令牌、密码或第三方密钥。
 */
@Service
public class OperationLogService {
    private final OperationLogRepository repository;

    public OperationLogService(OperationLogRepository repository) {
        this.repository = repository;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(String action, String target, String detail) {
        AuthUser user = CurrentUser.userOrNull();
        OperationLog entry = new OperationLog();
        if (user != null) {
            entry.setActorId(user.id());
            entry.setActorName(user.username());
        }
        entry.setAction(action);
        entry.setTarget(target);
        entry.setDetail(detail == null ? null : detail.substring(0, Math.min(500, detail.length())));
        repository.save(entry);
    }
}
