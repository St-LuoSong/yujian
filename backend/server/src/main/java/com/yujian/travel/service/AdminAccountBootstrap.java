package com.yujian.travel.service;

import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.UserAccountRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.Locale;

/**
 * Creates or promotes the optional operator account.
 *
 * Empty configuration means no privileged account exists, which is the right
 * default for a repository checkout. When configured, the password is re-applied
 * on every start so a rotated secret takes effect without manual SQL.
 */
@Component
public class AdminAccountBootstrap implements ApplicationRunner {
    private static final Logger log = LoggerFactory.getLogger(AdminAccountBootstrap.class);

    private final AppProperties properties;
    private final UserAccountRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public AdminAccountBootstrap(AppProperties properties, UserAccountRepository userRepository,
                                 PasswordEncoder passwordEncoder) {
        this.properties = properties;
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        AppProperties.Admin admin = properties.getAdmin();
        String username = admin.getUsername() == null ? "" : admin.getUsername().trim();
        String password = admin.getPassword() == null ? "" : admin.getPassword();
        if (username.isEmpty() || password.isEmpty()) {
            return;
        }
        String email = admin.getEmail() == null || admin.getEmail().isBlank()
            ? username.toLowerCase(Locale.ROOT) + "@yujian.local"
            : admin.getEmail().trim().toLowerCase(Locale.ROOT);

        UserAccount account = userRepository
            .findByUsernameIgnoreCaseOrEmailIgnoreCase(username, username)
            .orElseGet(UserAccount::new);
        account.setUsername(username);
        account.setEmail(email);
        account.setPasswordHash(passwordEncoder.encode(password));
        account.setEmailVerified(true);
        account.getRoles().add("ADMIN");
        account.getRoles().add("USER");
        userRepository.save(account);
        log.info("Operator account '{}' is ready with the ADMIN role", username);
    }
}
