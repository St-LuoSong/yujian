package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * 景点内容库。
 *
 * 公开接口 /api/pois 与管理台 /api/admin/pois 都读这张表，保证"管理台改了什么，游客端就看到什么"。
 * id 为业务主键（例如 longmen），可以被行程文本引用，所以不随内容更新而变化。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "poi", indexes = {
    @Index(name = "idx_poi_published_sort", columnList = "published, sort_order"),
    @Index(name = "idx_poi_city", columnList = "city")
})
public class PoiEntity {
    @Id
    @Column(length = 64)
    private String id;

    @Column(nullable = false, length = 80)
    private String name;

    @Column(nullable = false, length = 40)
    private String city;

    @Column(nullable = false, length = 40)
    private String category;

    @Column(name = "image_url", length = 500)
    private String imageUrl;

    @Column(nullable = false, length = 500)
    private String description;

    @Column(name = "ticket_from", nullable = false)
    private int ticketFrom;

    @Column(nullable = false, length = 40)
    private String duration;

    @Column(length = 120)
    private String suitability;

    @Column(name = "weather_tip", length = 300)
    private String weatherTip;

    /** 数据状态：实时数据 / 缓存数据 / 系统资料 / 演示数据。 */
    @Column(name = "data_status", nullable = false, length = 32)
    private String dataStatus;

    /** 图片来源与授权说明，交付时需要能逐条追溯。 */
    @Column(name = "image_credit", length = 200)
    private String imageCredit;

    @Column(name = "source_url", length = 300)
    private String sourceUrl;

    /**
     * 百度坐标系（BD09）下的经纬度。
     *
     * 行程地图优先用它：运营台里人工核对或一键解析过的坐标，比每次重新地理编码更可信，
     * 也不受百度配额与网络波动影响。允许为空 —— 为空时地图退回到按名称自动解析。
     */
    @Column(name = "lng")
    private Double lng;

    @Column(name = "lat")
    private Double lat;

    @Column(nullable = false)
    private boolean published;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
