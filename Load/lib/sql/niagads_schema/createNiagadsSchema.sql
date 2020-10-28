CREATE SCHEMA NIAGADS;

GRANT USAGE ON SCHEMA NIAGADS TO gus_r;
ALTER DEFAULT PRIVILEGES IN SCHEMA NIAGADS GRANT EXECUTE ON FUNCTIONS TO gus_r;

ALTER DEFAULT PRIVILEGES IN SCHEMA NIAGADS GRANT ALL ON TABLES TO gus_w;
ALTER DEFAULT PRIVILEGES IN SCHEMA NIAGADS GRANT ALL ON SEQUENCES TO gus_w;
ALTER DEFAULT PRIVILEGES IN SCHEMA NIAGADS GRANT ALL ON FUNCTIONS TO gus_w;
ALTER DEFAULT PRIVILEGES IN SCHEMA NIAGADS GRANT EXECUTE ON FUNCTIONS TO gus_w;

INSERT INTO core.DatabaseInfo
   (database_id, name, description, modification_date, user_read, user_write,
    group_read, group_write, other_read, other_write, row_user_id,
    row_group_id, row_project_id, row_alg_invocation_id)
SELECT nextval('core.databaseinfo_sq'), 'NIAGADS',
       'Application-specific data for the NIAGADS GenomicsDB website', now(),
       1, 1, 1, 1, 1, 1, 1, 1, p.project_id, 0
FROM (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p
WHERE LOWER('NIAGADS') NOT IN (SELECT LOWER(name) FROM core.DatabaseInfo);
