DROP TABLE dbSNPVariantClass;

CREATE TABLE dbSNPVariantClass (
  variation_abbreviation VARCHAR(32) NOT NULL
  , sequence_ontology_id VARCHAR(50) NOT NULL
  , variation_class VARCHAR(250) NOT NULL
);


INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('single nucleotide variant' ,'SO:0001483:SNV', 'SNV');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('insertion',  'SO:0000667:insertion',	'INS');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('deletion', 'SO:0000159:deletion', 'DEL');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('indel','SO:1000032:indel','INDEL');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('multiple nucleotide polymorphism','SO:0001013:MNP', 'MNP');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('multiple nucleotide variation', 'submitted request to Sequence Ontology',	'MNV');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('duplication', 	'SO:1000035:duplication', 	'DUP');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('sequence alteration', 	'SO:0001059:sequence_alteration', 	 'VAR');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('inversion', 	'SO:1000036:inversion', 	'INV');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('short tandem repeat (microsatellite)', 	'SO:0000289:microsatellite', 	'STR');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES  ('monomeric repeat', 	'SO:0001934:monomeric_repeat', 	'MON');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('copy number loss' 	,'SO:0001743:copy_number_loss' 	 ,'CNL');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('copy number gain', 	'SO:0001742:copy_number_gain', 	 'CNG');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('copy number variation',	'SO:0001019:copy_number_variation', 	'CNV');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('mobile element insertion',	'SO:1001837:mobile_element_insertion', 	'MEI');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('novel sequence insertion', 	'SO:1001838:novel_sequence_insertion', 	 'NSI');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('complex', 	'SO:0001784:complex_structural_alteration', 	 'CMPX');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('tandem duplication', 	'SO:1000173:tandem_duplication', 	 'TDM');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('translocation', 	'SO:0000199:translocation', 	 'TRN');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('no variation', 	'submitted request to Sequence Ontology',	 'NOVAR');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('deletion/insertion', 	'NA'	, 'DIV');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('variable, but undefined at nucleotide level', 	'NA'	, 'HERTEROZYGOUS');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('insertion/deletion of named repetitive element', 	'NA'	, 'NAMED');
INSERT INTO dbSNPVariantClass (variation_class, sequence_ontology_id, variation_abbreviation) VALUES ('cluster contains submissions from 2 or more alleleic classes', 	'NA'	, 'MIXED');
