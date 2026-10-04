package com.yujian.travel.repository;

import com.yujian.travel.domain.AppReleaseEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface AppReleaseRepository extends JpaRepository<AppReleaseEntity, UUID> {
    List<AppReleaseEntity> findAllByOrderByCreatedAtDesc();

    List<AppReleaseEntity> findByPlatformAndPackageNameAndChannelAndStatus(
        String platform, String packageName, String channel, String status);

    boolean existsByPackageNameAndChannelAndVersionCode(
        String packageName, String channel, long versionCode);

    Optional<AppReleaseEntity> findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
        String platform, String packageName, String channel, String status);

    Optional<AppReleaseEntity> findFirstByPlatformAndPackageNameAndChannelOrderByVersionCodeDesc(
        String platform, String packageName, String channel);

    Optional<AppReleaseEntity> findFirstByPlatformAndPackageNameAndChannelAndVersionCode(
        String platform, String packageName, String channel, long versionCode);

    Optional<AppReleaseEntity>
        findFirstByPlatformAndPackageNameAndChannelAndVersionCodeLessThanEqualOrderByVersionCodeDesc(
            String platform, String packageName, String channel, long versionCode);
}
