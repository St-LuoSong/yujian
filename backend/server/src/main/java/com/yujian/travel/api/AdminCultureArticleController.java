package com.yujian.travel.api;

import com.yujian.travel.service.ContentLibraryService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 文化锦囊管理。首版只允许管理员发布，不开放用户投稿。 */
@RestController
@RequestMapping("/api/admin/culture-articles")
public class AdminCultureArticleController {
    private final ContentLibraryService contentLibrary;
    private final OperationLogService operationLog;

    public AdminCultureArticleController(ContentLibraryService contentLibrary,
                                         OperationLogService operationLog) {
        this.contentLibrary = contentLibrary;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<ContentModels.CultureArticleView> list() {
        return contentLibrary.adminCultureArticles();
    }

    @GetMapping("/{id}")
    public ContentModels.CultureArticleView get(@PathVariable String id) {
        return contentLibrary.adminCultureArticle(id);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ContentModels.CultureArticleView create(@Valid @RequestBody ContentModels.CultureArticleInput input) {
        ContentModels.CultureArticleView created = contentLibrary.createCultureArticle(input);
        operationLog.record("CULTURE_ARTICLE_CREATE", "culture-article:" + created.id(), created.title());
        return created;
    }

    @PutMapping("/{id}")
    public ContentModels.CultureArticleView update(@PathVariable String id,
                                                   @Valid @RequestBody ContentModels.CultureArticleInput input) {
        ContentModels.CultureArticleView updated = contentLibrary.updateCultureArticle(id, input);
        operationLog.record("CULTURE_ARTICLE_UPDATE", "culture-article:" + id, updated.title());
        return updated;
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        contentLibrary.deleteCultureArticle(id);
        operationLog.record("CULTURE_ARTICLE_DELETE", "culture-article:" + id, null);
    }
}
