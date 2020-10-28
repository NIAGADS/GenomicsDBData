DROP TABLE SequenceAttributes;
CREATE TABLE SequenceAttributes (
  sequence_source_id TEXT NOT NULL PRIMARY KEY
, chromosome TEXT NOT NULL
, length INTEGER NOT NULL
, organism TEXT
, filename TEXT -- so we can use the InsertFile plugin
);

GRANT SELECT ON SequenceAttributes TO genomicsdb;
CREATE INDEX sequenceattributes_ind01 ON SequenceAttributes (chromosome);
-- run after load plugin
-- UPDATE SequenceAttributes SET organism = 'Homo sapiens';