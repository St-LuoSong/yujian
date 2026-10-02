package com.yujian.travel.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "trip_day")
public class TripDayEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "trip_plan_id", nullable = false)
    private TripPlanEntity tripPlan;

    @Column(nullable = false, length = 32)
    private String label;

    @Column(name = "date_label", nullable = false, length = 64)
    private String dateLabel;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @OneToMany(mappedBy = "day", cascade = CascadeType.ALL, orphanRemoval = true)
    @OrderBy("sortOrder ASC")
    private List<TripItemEntity> items = new ArrayList<>();

    public void addItem(TripItemEntity item) {
        item.setDay(this);
        items.add(item);
    }
}
