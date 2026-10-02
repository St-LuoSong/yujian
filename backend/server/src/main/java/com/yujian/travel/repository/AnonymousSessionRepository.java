package com.yujian.travel.repository;

import com.yujian.travel.domain.AnonymousSession;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface AnonymousSessionRepository extends JpaRepository<AnonymousSession, UUID> {
    Optional<AnonymousSession> findByTokenHash(String tokenHash);
}
