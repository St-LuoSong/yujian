package com.yujian.travel.repository;

import com.yujian.travel.domain.ToolInvocationLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public interface ToolInvocationLogRepository extends JpaRepository<ToolInvocationLog, UUID> {
    List<ToolInvocationLog> findByTripPlanIdOrderByCreatedAtAsc(UUID tripPlanId);

    long countBySuccessTrue();

    long countBySuccessFalse();

    long countByDataStatusContaining(String keyword);

    /** 其中"演示数据（降级）"那一部分：真实数据源不可用后由兜底数据顶上的调用。 */
    long countByDataStatusContainingAndErrorCodeIsNotNull(String keyword);

    /** 统计只读时间戳，不把 output_summary 等大字段读进内存。 */
    @Query("select l.createdAt from ToolInvocationLog l where l.createdAt >= :from")
    List<Instant> findCreatedAtFrom(@Param("from") Instant from);
}
