package com.yujian.travel.repository;

import com.yujian.travel.domain.EmailVerification;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface EmailVerificationRepository extends JpaRepository<EmailVerification, UUID> {
    Optional<EmailVerification> findTopByEmailAndPurposeOrderByCreatedAtDesc(String email, String purpose);
}
