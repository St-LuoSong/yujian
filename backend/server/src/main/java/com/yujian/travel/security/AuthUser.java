package com.yujian.travel.security;

import com.yujian.travel.domain.UserAccount;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

import java.util.Collection;
import java.util.Set;
import java.util.UUID;

public record AuthUser(UUID id, String username, String password, Set<String> roles, boolean enabled)
    implements UserDetails {

    public static AuthUser from(UserAccount user) {
        return new AuthUser(user.getId(), user.getUsername(), user.getPasswordHash(),
            Set.copyOf(user.getRoles()), true);
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return roles.stream()
            .map(role -> role.startsWith("ROLE_") ? role : "ROLE_" + role)
            .map(SimpleGrantedAuthority::new)
            .toList();
    }

    @Override
    public String getPassword() {
        return password;
    }

    @Override
    public String getUsername() {
        return username;
    }

    @Override
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    public boolean isCredentialsNonExpired() {
        return true;
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }
}
