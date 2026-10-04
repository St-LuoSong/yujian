-- ---------------------------------------------------------------------------
-- V7：文化锦囊补两个运营字段
-- ---------------------------------------------------------------------------
-- author     署名（编辑部 / 特约作者）。为空表示运营台还没填，客户端不显示。
-- like_count 展示用点赞数，由运营台维护：文化内容多来自公众号或专栏转载，
--            点赞数是随内容一起搬过来的元数据。将来要做站内真实点赞，
--            再开一张 culture_article_like 表，这一列可以当作初始值，
--            不需要推翻现在的结构。
-- ---------------------------------------------------------------------------

alter table culture_article
    add column author varchar(80) null after category;

alter table culture_article
    add column like_count integer not null default 0 after author;
