-- ---------------------------------------------------------------------------
-- V4：评论二级回复、评论点赞、更新通知的去重键
-- ---------------------------------------------------------------------------

-- ---------- 1. 二级评论 ----------

-- parent_id 为空表示这是一条顶层评论；非空表示它是对某条顶层评论的回复。
-- 只做两层：回复的回复仍然挂到同一条顶层评论下，UI 按"一层 + 平铺回复"渲染，
-- 不做无限嵌套 —— 手机屏幕上三层以上的缩进会先把正文挤没。
alter table community_comment
    add column parent_id binary(16) null after post_id;

alter table community_comment
    add column like_count bigint not null default 0 after content;

create index idx_community_comment_parent on community_comment (parent_id, created_at);

-- 顶层评论被删除时，它的回复一起走：留下 parent_id 指向已删行的孤儿回复，
-- 界面上既显示不出来也删不掉。
alter table community_comment
    add constraint fk_community_comment_parent
        foreign key (parent_id) references community_comment (id) on delete cascade;

-- ---------- 2. 评论点赞 ----------

create table if not exists community_comment_like (
    id         binary(16)  not null,
    comment_id binary(16)  not null,
    user_id    binary(16)  not null,
    created_at datetime(6) not null,
    primary key (id),
    constraint uk_community_comment_like unique (user_id, comment_id),
    constraint fk_community_comment_like_comment
        foreign key (comment_id) references community_comment (id) on delete cascade,
    constraint fk_community_comment_like_user
        foreign key (user_id) references user_account (id)
) engine=InnoDB default charset=utf8mb4;

-- ---------- 3. 消息去重键 ----------

-- 更新通知必须"一个版本只发一次"。没有这个键的话，客户端每次启动都会 ack 一次，
-- 用户会在消息中心里攒下一整列内容相同的"新版本已安装"。
-- MySQL 的唯一索引允许多个 NULL，所以原有的种子消息（dedupe_key 为空）不受影响。
alter table user_message
    add column dedupe_key varchar(120) null after type;

alter table user_message
    add constraint uk_user_message_dedupe unique (user_id, dedupe_key);
