package com.yujian.travel.repository;

import com.yujian.travel.domain.AppSettingEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AppSettingRepository extends JpaRepository<AppSettingEntity, String> {
}
