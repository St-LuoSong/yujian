package com.yujian.travel.service;

import com.yujian.travel.repository.FavoriteRepository;
import com.yujian.travel.repository.RefreshTokenRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.TripShareRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.UUID;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class AccountDeletionServiceTest {
    @Test
    void deletesDependentRowsBeforeTheAccount() {
        TripShareRepository shares = mock(TripShareRepository.class);
        TripPlanRepository trips = mock(TripPlanRepository.class);
        FavoriteRepository favorites = mock(FavoriteRepository.class);
        RefreshTokenRepository tokens = mock(RefreshTokenRepository.class);
        UserAccountRepository users = mock(UserAccountRepository.class);
        AccountDeletionService service =
            new AccountDeletionService(shares, trips, favorites, tokens, users);
        UUID userId = UUID.randomUUID();
        when(trips.findByOwnerIdOrderByUpdatedAtDesc(userId)).thenReturn(List.of());

        service.delete(userId);

        var order = inOrder(shares, trips, favorites, tokens, users);
        order.verify(shares).deleteByTripPlanOwnerId(userId);
        order.verify(trips).deleteAll(List.of());
        order.verify(favorites).deleteByUserId(userId);
        order.verify(tokens).deleteByUserId(userId);
        order.verify(users).deleteById(userId);
    }
}
