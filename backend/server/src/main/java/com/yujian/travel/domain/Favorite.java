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
@Table(name = "favorite", uniqueConstraints = {
    @UniqueConstraint(name = "uk_favorite_user_poi", columnNames = {"user_id", "poi_id"})
})
public class Favorite {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private UserAccount user;

    @Column(name = "poi_id", nullable = false, length = 64)
    private String poiId;

    @Column(name = "poi_name", nullable = false, length = 160)
    private String poiName;

    @Column(name = "city", length = 64)
    private String city;

    @Column(name = "image_url", length = 600)
    private String imageUrl;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
