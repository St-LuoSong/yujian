package com.yujian.travel.map;

import com.yujian.travel.config.AppProperties;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 底图票据的守护测试。
 *
 * 底图接口是 permitAll 的（CachedNetworkImage 带不了鉴权头），
 * 因此票据是它唯一的门禁：这里锁住"换参数就失效""过期就失效""伪造无效"三条底线。
 */
class MapTicketServiceTest {
    private static final long HOUR = 3600L;
    /** 固定时间戳，让测试可重复。 */
    private static final long NOW = 1780293296L;

    private final MapTicketService service = new MapTicketService(new AppProperties());

    private static String canonical() {
        return MapTicketService.canonical(113.65, 34.76, 12, 1024, 768);
    }

    @Test
    @DisplayName("同一组参数签发的票据可以通过校验")
    void verifiesOwnTicket() {
        String ticket = service.issue(canonical(), NOW);
        assertThat(service.verify(canonical(), ticket, NOW)).isTrue();
    }

    @Test
    @DisplayName("参数被改动（中心点 / 缩放 / 尺寸）票据立即失效")
    void rejectsTamperedParameters() {
        String ticket = service.issue(canonical(), NOW);
        assertThat(service.verify(MapTicketService.canonical(113.66, 34.76, 12, 1024, 768), ticket, NOW)).isFalse();
        assertThat(service.verify(MapTicketService.canonical(113.65, 34.76, 13, 1024, 768), ticket, NOW)).isFalse();
        assertThat(service.verify(MapTicketService.canonical(113.65, 34.76, 12, 1024, 769), ticket, NOW)).isFalse();
    }

    @Test
    @DisplayName("过期后失效，有效期不超过两个整点窗口")
    void expiresAndStaysBounded() {
        String ticket = service.issue(canonical(), NOW);
        long expiresAt = Long.parseLong(ticket.substring(0, ticket.indexOf('.')));
        assertThat(expiresAt).isGreaterThan(NOW);
        assertThat(expiresAt - NOW).isLessThanOrEqualTo(2 * HOUR);
        assertThat(service.verify(canonical(), ticket, expiresAt - 1)).isTrue();
        assertThat(service.verify(canonical(), ticket, expiresAt)).isFalse();
        assertThat(service.verify(canonical(), ticket, expiresAt + 60)).isFalse();
    }

    @Test
    @DisplayName("伪造的票据一律拒绝")
    void rejectsForgedTickets() {
        assertThat(service.verify(canonical(), null, NOW)).isFalse();
        assertThat(service.verify(canonical(), "", NOW)).isFalse();
        assertThat(service.verify(canonical(), "abc", NOW)).isFalse();
        assertThat(service.verify(canonical(), "9999999999.", NOW)).isFalse();
        assertThat(service.verify(canonical(), (NOW + 3600) + ".deadbeef", NOW)).isFalse();
        // 自签一个远超上限的过期时间：签名有效也不接受。
        String farFuture = service.issue(canonical(), NOW + 10 * HOUR);
        assertThat(service.verify(canonical(), farFuture, NOW)).isFalse();
    }

    @Test
    @DisplayName("同一小时内签发的票据完全一致：客户端磁盘缓存因此仍然有效")
    void ticketIsStableWithinAnHour() {
        assertThat(service.issue(canonical(), NOW)).isEqualTo(service.issue(canonical(), NOW + 120));
    }

    @Test
    @DisplayName("剩余有效期参与缓存时长计算")
    void reportsRemainingSeconds() {
        String ticket = service.issue(canonical(), NOW);
        assertThat(service.remainingSeconds(ticket, NOW)).isGreaterThan(HOUR);
        assertThat(service.remainingSeconds("坏票据", NOW)).isZero();
    }
}
