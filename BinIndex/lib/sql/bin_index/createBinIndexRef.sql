-- table for Bin Index Reference
DROP TABLE IF EXISTS BinIndexRef;

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS ltree;

CREATE TABLE BinIndexRef (
       BIN_INDEX_ID     SERIAL NOT NULL PRIMARY KEY,
       CHROMOSOME           CHARACTER VARYING(10) NOT NULL,
       LEVEL		    INTEGER NOT NULL,
       GLOBAL_BIN                  INTEGER NOT NULL,
       GLOBAL_BIN_PATH		    LTREE NOT NULL,
       LOCATION			    INT8RANGE NOT NULL
);

-- ADDITIONAL CONSTRAINTS



-- INDEXES

CREATE INDEX BININDEXREF_INDX01 ON BinIndexRef USING BRIN (CHROMOSOME);
CREATE INDEX BININDEXREF_INDX02 ON BinIndexRef(CHROMOSOME, LEVEL);
CREATE INDEX BININDEXREF_INDX03 ON BinIndexRef(GLOBAL_BIN);
CREATE INDEX BININDEXREF_INDX04 ON BinIndexRef USING GIST(GLOBAL_BIN_PATH);
CREATE INDEX BININDEXREF_INDX05 ON BinIndexRef USING GIST(chromosome, location);
