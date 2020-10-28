-- table for variant score (e.g., CADD/CATO) result
-- partitioned on the protocol app node
DROP TABLE IF EXISTS Results.VariantScore;
DROP SEQUENCE IF EXISTS Results.VariantScore_SQ;

CREATE UNLOGGED TABLE Results.VariantScore  (
       --VARIANT_SCORE_ID	     BIGSERIAL NOT NULL,
       PROTOCOL_APP_NODE_ID	     NUMERIC(12) NOT NULL,
       PROTOCOL_APP_NODE_SOURCE_ID	     CHARACTER VARYING(25) NOT NULL,
       VARIANT_ID		     INTEGER NOT NULL,
       BIN_INDEX		     LTREE,
       VARIANT_RECORD_PK	     CHARACTER VARYING(800) NOT NULL, -- chr:pos:ref:alt id,
       SCORE1 			     FLOAT NOT NULL,
       SCORE2 			     FLOAT,
       ANNOTATION	JSONB,
       
       -- GUS HOUSEKEEPING

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
       ROW_ALG_INVOCATION_ID	 NUMERIC(12)
) PARTITION BY LIST (PROTOCOL_APP_NODE_SOURCE_ID);


CREATE TABLE Results.VariantScore_CADD PARTITION OF Results.VariantScore FOR VALUES IN ('CADD');
CREATE TABLE Results.VariantScore_CATO PARTITION OF Results.VariantScore FOR VALUES IN ('CATO');


-- CONSTRAINTS

--ALTER TABLE Results.VariantScore ADD CONSTRAINT CONST_VScore_PROTOCOL_APP_NODE_ID FOREIGN KEY (protocol_app_node_id) REFERENCES Study.ProtocolAppNode (protocol_app_node_id);
--ALTER TABLE Results.VariantScore ADD CONSTRAINT CONST_VScore_VARIANT_ID FOREIGN KEY (variant_id) REFERENCES NIAGADS.Variant (variant_id);

-- INDEXES

--CREATE INDEX Score_RESULT_IND01 ON Results.VariantScore USING BRIN(PROTOCOL_APP_NODE_ID);
--CREATE INDEX Score_RESULT_IND02 ON Results.VariantScore (variant_record_pk);
--CREATE INDEX Score_RESULT_IND03 ON Results.VariantScore (score1,variant_record_pk);
--CREATE INDEX Score_RESULT_IND04 ON Results.VariantScore (score2,variant_record_pk);
--CREATE INDEX Score_RESULT_IND05 ON Results.VariantScore USING GIST(BIN_INDEX);

-- GRANTS

GRANT SELECT ON Results.VariantScore TO gus_r;
GRANT INSERT, SELECT, UPDATE, DELETE ON Results.VariantScore TO gus_w;

-- SEQUENCES

CREATE SEQUENCE Results.VariantScore_SQ;
GRANT SELECT ON Results.VariantScore_SQ TO gus_w;
GRANT SELECT ON Results.VariantScore_SQ TO gus_r;

-- GUS CORE

INSERT INTO Core.TableInfo
    (table_id, name, table_type, primary_key_column, database_id, is_versioned,
     is_view, view_on_table_id, superclass_table_id, is_updatable,
     modification_date, user_read, user_write, group_read, group_write,
     other_read, other_write, row_user_id, row_group_id, row_project_id,
     row_alg_invocation_id)
SELECT nextval('core.tableinfo_sq'), 'VariantScore',
       'Standard', 'VARIANT_SCORE_ID',
       d.database_id, 0, 0, NULL, NULL, 1,now(), 1, 1, 1, 1, 1, 1, 1, 1,
       p.project_id, 0
FROM 
     (SELECT MAX(project_id) AS project_id FROM core.ProjectInfo) p,
     (SELECT database_id FROM core.DatabaseInfo WHERE NAME = 'Results') d
WHERE 'VariantScore' NOT IN (SELECT NAME FROM Core.TableInfo
                                    WHERE database_id = d.database_id);

