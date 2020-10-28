-- table for variant effect predictions
DROP TABLE IF EXISTS NIAGADS.LinkageDisequilibrium;
DROP SEQUENCE IF EXISTS NIAGADS.LinkageDisequilibrium_SQ;

CREATE TABLE NIAGADS.LinkageDisequilibrium (
       LINKAGE_DISEQ_ID			SERIAL NOT NULL PRIMARY KEY,
       PROTOCOL_APP_NODE_ID		NUMERIC(10) NOT NULL,
       NA_FEATURE_ID_A			        NUMERIC(12) NOT NULL,
       NA_FEATURE_ID_B		 	NUMERIC(12) NOT NULL,	
       VARIANT_PRIMARY_KEY_A		CHARACTER VARYING(500) NOT NULL,
       VARIANT_PRIMARY_KEY_B		CHARACTER VARYING(500) NOT NULL,
       MINOR_ALLELE_FREQ_A		FLOAT NOT NULL,
       MINOR_ALLELE_FREQ_B		FLOAT NOT NULL,
       R_SQUARED			FLOAT NOT NULL,
       DPRIME				FLOAT NOT NULL,


       MODIFICATION_DATE	 DATE,
       USER_READ		 NUMERIC(1),
       USER_WRITE		 NUMERIC(1),
       GROUP_READ		 NUMERIC(10),
       GROUP_WRITE 		 NUMERIC(1),
       OTHER_READ		 NUMERIC(1),
       OTHER_WRITE		 NUMERIC(1),
       ROW_USER_ID		 NUMERIC(12),
       ROW_GROUP_ID		 NUMERIC(4),
       ROW_PROJECT_ID		 NUMERIC(4),
       ROW_ALG_INVOCATION_ID	 NUMERIC(12),

       --FOREIGN KEY (NA_FEATURE_ID_A) REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID),
       --FOREIGN KEY (NA_FEATURE_ID_B) REFERENCES DoTS.NAFeatureImp(NA_FEATURE_ID),
       FOREIGN KEY (PROTOCOL_APP_NODE_ID) REFERENCES Study.ProtocolAppNode(PROTOCOL_APP_NODE_ID)
);


CREATE INDEX LD_IND01 ON NIAGADS.LinkageDisequilibrium (VARIANT_PRIMARY_KEY_A);
CREATE INDEX LD_IND02 ON NIAGADS.LinkageDisequilibrium (VARIANT_PRIMARY_KEY_B);
CREATE INDEX LD_IND03 ON NIAGADS.LinkageDisequilibrium (MINOR_ALLELE_FREQ_A);
CREATE INDEX LD_IND04 ON NIAGADS.LinkageDisequilibrium (MINOR_ALLELE_FREQ_B);
CREATE INDEX LD_IND05 ON NIAGADS.LinkageDisequilibrium (R_SQUARED);
CREATE INDEX LD_IND06 ON NIAGADS.LinkageDisequilibrium (PROTOCOL_APP_NODE_ID);
CREATE INDEX LD_IND07 ON NIAGADS.LinkageDisequilibrium (NA_FEATURE_ID_A);
CREATE INDEX LD_IND08 ON NIAGADS.LinkageDisequilibrium (NA_FEATURE_ID_B);

GRANT SELECT ON NIAGADS.LinkageDisequilibrium TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON NIAGADS.LinkageDisequilibrium TO gus_w;

CREATE SEQUENCE NIAGADS.LinkageDisequilibrium_SQ;
GRANT SELECT ON NIAGADS.LinkageDisequilibrium_SQ TO gus_w;
GRANT SELECT ON NIAGADS.LinkageDisequilibrium_SQ TO gus_r;

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'LinkageDisequilibrium',
       'Standard', 'LINKAGE_DISEQ_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'NIAGADS') d
WHERE 'LinkageDisequilibrium' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

