-- indexes to improve text / like searches

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX OT_NAME_GIN_TRGM_IDX ON SRes.OntologyTerm(name);
CREATE INDEX OT_DEFINITION_GIN_TRGM_IDX ON SRes.OntologyTerm(definition);
