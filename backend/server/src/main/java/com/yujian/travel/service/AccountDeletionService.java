package com.yujian.travel.service;

import com.yujian.travel.domain.TripPlanEntity;
import com.yujian.travel.repository.FavoriteRepository;
import com.yujian.travel.repository.RefreshTokenRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.TripShareRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * 用户主动删除账号时的级联清理。
 *
 * 顺序由外键关系决定：先删分享，再删行程（行程会级联删除逐日节点），
 * 然后删收藏与刷新令牌，最后删账号。整个过程在一个事务里，任一步失败都不会留下半删状态。
 */
@Service
public class AccountDeletionService {
    private final TripShareRepository tripShareRepository;
    private final TripPlanRepository tripPlanRepository;
    private final FavoriteRepository favoriteRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final UserAccountRepository userRepository;

    public AccountDeletionService(TripShareRepository tripShareRepository,
                                  TripPlanRepository tripPlanRepository,
                                  FavoriteRepository favoriteRepository,
                                  RefreshTokenRepository refreshTokenRepository,
                                  UserAccountRepository userRepository) {
        this.tripShareRepository = tripShareRepository;
        this.tripPlanRepository = tripPlanRepository;
        this.favoriteRepository = favoriteRepository;
        this.refreshTokenRepository = refreshTokenRepository;
        this.userRepository = userRepository;
    }

    @Transactional
    public void delete(UUID userId) {
        tripShareRepository.deleteByTripPlanOwnerId(userId);
        List<TripPlanEntity> plans = tripPlanRepository.findByOwnerIdOrderByUpdatedAtDesc(userId);
        tripPlanRepository.deleteAll(plans);
        favoriteRepository.deleteByUserId(userId);
        refreshTokenRepository.deleteByUserId(userId);
        userRepository.deleteById(userId);
    }
}
