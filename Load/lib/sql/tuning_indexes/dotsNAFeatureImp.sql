/* 
DROP INDEX DoTS.NAFeatureImp_IND01;
DROP INDEX DoTS.NAFeatureImp_IND02;
DROP INDEX DoTS.NAFeatureImp_IND03; 
*/

CREATE INDEX NAFeatureImp_IND01 ON DoTS.NAFeatureImp(subclass_view);
CREATE INDEX NAFeatureImp_IND02 ON DoTS.NAFeatureImp(subclass_view, source_id);
CREATE INDEX NAFeatureImp_IND03 ON DoTS.NAFeatureImp(na_sequence_id) WHERE subclass_view IN ('GeneFeature', 'ExonFeature', 'Transcript');


