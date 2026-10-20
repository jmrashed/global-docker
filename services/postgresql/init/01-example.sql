-- Runs once, on first init of the postgres_data volume only.
-- Example per-project database and role. Copy and rename per project.
CREATE ROLE example_app LOGIN PASSWORD 'example_app_secret';
CREATE DATABASE example_app OWNER example_app;
