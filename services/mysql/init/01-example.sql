-- Runs once, on first init of the mysql_data volume only.
-- Example per-project database and user. Copy and rename per project.
CREATE DATABASE IF NOT EXISTS `example_app` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'example_app'@'%' IDENTIFIED BY 'example_app_secret';
GRANT ALL PRIVILEGES ON `example_app`.* TO 'example_app'@'%';
FLUSH PRIVILEGES;
