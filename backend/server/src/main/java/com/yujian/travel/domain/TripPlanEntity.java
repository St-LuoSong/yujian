package com.yujian.travel.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "trip_plan", indexes = {
    @Index(name = "idx_trip_plan_owner", columnList = "user_id, updated_at"),
    @Index(name = "idx_trip_plan_anonymous", columnList = "anonymous_session_id, updated_at")
})
public class TripPlanEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id")
    private UserAccount owner;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "anonymous_session_id")
    private AnonymousSession anonymousSession;

    @Column(nullable = false, length = 160)
    private String title;

    @Column(nullable = false, length = 600)
    private String summary;

    @Column(nullable = false, length = 80)
    private String corridor;

    @Column(nullable = false, length = 32)
    private String intensity;

    @Column(nullable = false, length = 1000)
    private String prompt;

    @Column(length = 80)
    private String origin;

    @Column(length = 80)
    private String destination;

    @Column(name = "days_count", nullable = false)
    private int daysCount;

    @Column(nullable = false)
    private int travelers;

    @Column(name = "budget_per_person")
    private Integer budgetPerPerson;

    @Column(name = "total_cost", nullable = false)
    private int totalCost;

    @Column(name = "per_person_cost", nullable = false)
    private int perPersonCost;

    @Column(name = "data_status", nullable = false, length = 32)
    private String dataStatus;

    @Column(name = "planning_engine", length = 64)
    private String planningEngine;

    @Column(name = "prompt_version", length = 64)
    private String promptVersion;

    @Column(name = "tool_mock_count")
    private Integer toolMockCount;

    @Column(nullable = false)
    private int snapshotVersion;

    @Lob
    @Column(name = "previous_snapshot")
    private String previousSnapshot;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "trip_plan_warning", joinColumns = @JoinColumn(name = "trip_plan_id"))
    @Column(name = "warning_text", nullable = false, length = 500)
    private List<String> warnings = new ArrayList<>();

    @OneToMany(mappedBy = "tripPlan", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("sortOrder ASC")
    private List<TripDayEntity> days = new ArrayList<>();

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    public void replaceDays(List<TripDayEntity> nextDays) {
        days.clear();
        nextDays.forEach(this::addDay);
    }

    public void addDay(TripDayEntity day) {
        day.setTripPlan(this);
        days.add(day);
    }

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
        if (snapshotVersion < 1) {
            snapshotVersion = 1;
        }
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
