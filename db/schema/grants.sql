BEGIN;

CREATE USER inspector WITH PASSWORD 'NetoSQL2025';

GRANT ALL PRIVILEGES ON SCHEMA egorov_food TO inspector;
GRANT USAGE ON SCHEMA information_schema, pg_catalog, exts TO inspector;
GRANT SELECT ON information_schema.tables, pg_catalog.pg_tables TO inspector;
GRANT EXECUTE ON FUNCTION exts.uuid_generate_v4() TO inspector;

GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON ALL TABLES IN SCHEMA egorov_food TO inspector;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA egorov_food TO inspector;

COMMIT;
