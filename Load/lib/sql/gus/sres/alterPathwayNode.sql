ALTER TABLE SRes.PathwayNode ADD COLUMN evidence_code CHARACTER VARYING(10);

CREATE INDEX PWYNODE_IND01 ON SRes.PathwayNode(evidence_code);
