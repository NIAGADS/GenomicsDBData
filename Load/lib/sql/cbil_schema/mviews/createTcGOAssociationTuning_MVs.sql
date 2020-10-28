/* prejoins of gene-GO associations; expanded view for transitive closure 
depends on CBIL.GOAssociation (see createGOAssociationTuning_MVs.sql)
*/

DROP MATERIALIZED VIEW IF EXISTS CBIL.GOAssociation_TC CASCADE;

CREATE MATERIALIZED VIEW CBIL.GOAssociation_TC AS (
  SELECT * FROM ( -- b/c of the union
       SELECT DISTINCT 
       subject.gene_id
       , subject.source_id
       , r.object_term_id AS ontology_term_id
       , obj.name AS go_term
       , replace(obj.source_id, '_', ':') AS go_term_id
       , 'closure' AS evidence_code
       , subject.taxon_id
       , subject.organism
       , subject.ontology
       , subject.ontology_abbrev
       FROM SRes.OntologyRelationship r,
       SRes.ExternalDatabaseRelease rls,
       CBIL.GoAssociation subject,
       SRes.OntologyTerm obj
       WHERE rls.version = 'go-transitive-closure'
       AND r.external_database_release_id = rls.external_database_release_id
       AND subject.ontology_term_id = r.subject_term_id -- don't worry about terms that are not annotated
       AND obj.ontology_term_id = r.object_term_id
       AND r.object_term_id != r.subject_term_id

       UNION

       SELECT * FROM CBIL.GoAssociation
  ) a
);


CREATE INDEX GOAssociation_TC_ind01 ON CBIL.GOAssociation_TC(source_id, go_term, go_term_id);
CREATE INDEX GOAssociation_TC_ind02 ON CBIL.GOAssociation_TC(ontology, source_id);
CREATE INDEX GOAssociation_TC_ind03 ON CBIL.GOAssociation_TC(go_term_id);
CREATE INDEX GOAssociation_TC_ind04 ON CBIL.GOAssociation_TC(gene_id);
CREATE INDEX GOAssociation_TC_ind05 ON CBIL.GOAssociation_TC(ontology_term_id);
CREATE INDEX GOAssociation_TC_ind06 ON CBIL.GOAssociation_TC(ontology_abbrev, source_id);
CREATE INDEX GOAssociation_TC_ind07 ON CBIL.GOAssociation_TC(organism);
CREATE INDEX GOAssociation_TC_ind08 ON CBIL.GOAssociation_TC(taxon_id);

GRANT SELECT ON CBIL.GOAssociation_TC TO gus_r, gus_w, comm_wdk_w;

-- counts of genes per term

DROP MATERIALIZED VIEW IF EXISTS CBIL.GOTerm_TC;

CREATE MATERIALIZED VIEW CBIL.GOTerm_TC AS (
SELECT ontology_term_id
, ontology
, ontology_abbrev
, go_term
, go_term_id
, taxon_id
, organism
, COUNT(DISTINCT source_id) AS num_annotated_genes
FROM CBIL.GOAssociation_TC 
GROUP BY ontology_term_id, ontology, ontology_abbrev, go_term, go_term_id, organism, taxon_id
);

CREATE UNIQUE INDEX GOTerm_TC_06 ON CBIL.GOTerm_TC (organism, ontology_term_id, num_annotated_genes);
CREATE INDEX GOTerm_TC_ind01 ON CBIL.GOTerm_TC (go_term, go_term_id);
CREATE INDEX GOTerm_TC_ind02 ON CBIL.GOTerm_TC (go_term_id, ontology_term_id);
CREATE INDEX GOTerm_TC_ind03 ON CBIL.GOTerm_TC (ontology_abbrev, go_term_id, go_term, num_annotated_genes);
CREATE INDEX GOTerm_TC_ind04 ON CBIL.GOTerm_TC (organism);
CREATE INDEX GOTerm_TC_ind05 ON CBIL.GOTerm_TC (taxon_id);

GRANT SELECT ON CBIL.GOTerm_TC TO comm_wdk_w;
