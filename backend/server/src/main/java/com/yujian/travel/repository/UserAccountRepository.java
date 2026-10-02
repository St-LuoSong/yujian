package com.yujian.travel.repository;

import com.yujian.travel.domain.UserAccount;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface UserAccountRepository extends JpaRepository<UserAccount, UUID> {
    Optional<UserAccount> findByUsernameIgnoreCase(String username);

    Optional<UserAccount> findByEmailIgnoreCase(String email);

    Optional<UserAccount> findByUsernameIgnoreCaseOrEmailIgnoreCase(String username, String email);

    boolean existsByUsernameIgnoreCase(String username);

    boolean existsByEmailIgnoreCase(String email);

    long countByEmailVerifiedTrue();

    @Query("select u.createdAt from UserAccount u where u.createdAt >= :from")
    List<Instant> findCreatedAtFrom(@Param("from") Instant from);
}
