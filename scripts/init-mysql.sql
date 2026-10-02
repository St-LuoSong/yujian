-- ---------------------------------------------------------------------------
-- 豫见智旅 —— 本机 MySQL 8 开发库初始化
--
-- 与 docker-compose.yml 的默认值保持一致：
--   database = yujian_travel   user = yujian   password = yujian_dev_password
--
-- 全部语句幂等（IF NOT EXISTS + ALTER USER），重复执行不会破坏已有数据。
-- 生产环境必须换成独立强口令，并且不要把真实口令提交进仓库。
-- 用法见 scripts\init-mysql.cmd。
-- ---------------------------------------------------------------------------

CREATE DATABASE IF NOT EXISTS yujian_travel
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

-- 本机 TCP 连接可能被解析成 localhost / 127.0.0.1 / % 三种主机名，
-- 三个都建上，避免"库里明明有账号却 Access denied"。
CREATE USER IF NOT EXISTS 'yujian'@'localhost' IDENTIFIED BY 'yujian_dev_password';
ALTER  USER 'yujian'@'localhost' IDENTIFIED BY 'yujian_dev_password';
GRANT ALL PRIVILEGES ON yujian_travel.* TO 'yujian'@'localhost';

CREATE USER IF NOT EXISTS 'yujian'@'127.0.0.1' IDENTIFIED BY 'yujian_dev_password';
ALTER  USER 'yujian'@'127.0.0.1' IDENTIFIED BY 'yujian_dev_password';
GRANT ALL PRIVILEGES ON yujian_travel.* TO 'yujian'@'127.0.0.1';

CREATE USER IF NOT EXISTS 'yujian'@'%' IDENTIFIED BY 'yujian_dev_password';
ALTER  USER 'yujian'@'%' IDENTIFIED BY 'yujian_dev_password';
GRANT ALL PRIVILEGES ON yujian_travel.* TO 'yujian'@'%';

FLUSH PRIVILEGES;

SELECT 'yujian_travel is ready' AS result;
