package com.yujian.travel.repository;

import com.yujian.travel.domain.CultureArticleEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface CultureArticleRepository extends JpaRepository<CultureArticleEntity, String> {
    List<CultureArticleEntity> findByPublishedTrueOrderBySortOrderAscCreatedAtDesc();

    List<CultureArticleEntity> findByPublishedTrueAndCategoryOrderBySortOrderAscCreatedAtDesc(String category);

    List<CultureArticleEntity> findAllByOrderBySortOrderAscCreatedAtDesc();
}
