package com.yujian.travel.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "trip_item")
public class TripItemEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_day_id", nullable = false)
    private TripDayEntity day;

    @Column(name = "item_type", nullable = false, length = 32)
    private String itemType;

    @Column(nullable = false, length = 160)
    private String title;

    @Column(length = 600)
    private String description;

    @Column(name = "start_time", length = 16)
    private String startTime;

    @Column(name = "end_time", length = 16)
    private String endTime;

    @Column(name = "duration_minutes")
    private Integer durationMinutes;

    @Column(name = "transport_mode", length = 80)
    private String transportMode;

    @Column(name = "distance_meters")
    private Integer distanceMeters;

    @Column(name = "estimated_cost", nullable = false)
    private int estimatedCost;

    @Column(length = 160)
    private String source;

    @Column(name = "data_status", nullable = false, length = 32)
    private String dataStatus;

    @Column(name = "feasibility_status", nullable = false, length = 32)
    private String feasibilityStatus;

    @Column(name = "risk_warnings", length = 1000)
    private String riskWarnings;

    @Column(name = "alternative_title", length = 160)
    private String alternativeTitle;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    @PreUpdate
    void touch() {
        updatedAt = Instant.now();
    }
}
