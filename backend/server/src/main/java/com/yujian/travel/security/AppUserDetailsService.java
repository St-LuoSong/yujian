package com.yujian.travel.security;

import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.UserAccountRepository;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class AppUserDetailsService implements UserDetailsService {
    private final UserAccountRepository userRepository;

    public AppUserDetailsService(UserAccountRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String identifier) throws UsernameNotFoundException {
        UserAccount user = userRepository.findByUsernameIgnoreCaseOrEmailIgnoreCase(identifier, identifier)
            .orElseThrow(() -> new UsernameNotFoundException("用户不存在"));
        return AuthUser.from(user);
    }
}
