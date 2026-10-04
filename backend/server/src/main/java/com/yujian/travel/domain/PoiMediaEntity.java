package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * 景区图集里的一张图。
 *
 * 与 poi.image_url（封面）分开：封面只有一个、是必填展示位；图集是 0..N 张，
 * 运营台可以随时增删。详情页按 sortOrder 顺序取，空图集时只显示封面。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "poi_media")
public class PoiMediaEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "poi_id", nullable = false, length = 64)
    private String poiId;

    @Column(name = "image_url", nullable = false, length = 600)
    private String imageUrl;

    @Column(length = 200)
    private String caption;

    @Column(name = "image_credit", length = 200)
    private String imageCredit;

    @Column(name = "source_url", length = 300)
    private String sourceUrl;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(nullable = false)
    private boolean published;
}
