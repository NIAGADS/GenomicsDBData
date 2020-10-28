/* prejoin of gene -> terms */

DROP MATERIALIZED VIEW IF EXISTS CBIL.GOAssociation CASCADE;

CREATE MATERIALIZED VIEW CBIL.GOAssociation AS (
SELECT g.gene_id
, g.source_id  	 
, goterm.ontology_term_id
, goterm.name AS go_term
, replace(goterm.source_id, '_', ':') AS go_term_id
, string_agg(evidence.name, ',') AS evidence_code
, g.ncbi_tax_id AS taxon_id
, g.organism
, initcap(replace(at.name, '_', ' ')) AS ontology
, CASE WHEN at.name = 'biological_process' THEN 'BP'
WHEN at.name = 'cellular_component' THEN 'CC'
ELSE 'MF' END AS ontology_abbrev
FROM 
DoTS.GOAssociationInstance goi,
DoTs.GOAssocInstEvidCode goc,
DoTs.GoAssociation goa,
SRes.OntologyTerm goterm,
SRes.OntologyTerm evidence,
SRes.OntologyTerm at,
CBIL.GeneAttributes g
WHERE goa.go_association_id = goi.go_association_id
AND goi.go_association_instance_id = goc.go_association_instance_id
AND evidence.ontology_term_id = goc.go_evidence_code_id
AND goa.go_term_id = goterm.ontology_term_id
AND goterm.ancestor_term_id = at.ontology_term_id
AND goa.row_id = g.gene_id
GROUP BY g.gene_id, g.source_id, g.ncbi_tax_id, g.organism, goterm.ontology_term_id, go_term, go_term_id, ontology, ontology_abbrev
);

CREATE INDEX GOAssociation_ind01 ON CBIL.GOAssociation(source_id, go_term, go_term_id);
CREATE INDEX GOAssociation_ind02 ON CBIL.GOAssociation(ontology, source_id);
CREATE INDEX GOAssociation_ind03 ON CBIL.GOAssociation(go_term_id);
CREATE INDEX GOAssociation_ind04 ON CBIL.GOAssociation(gene_id);
CREATE INDEX GOAssociation_ind05 ON CBIL.GOAssociation(ontology_term_id);
CREATE INDEX GOAssociation_ind06 ON CBIL.GOAssociation(ontology_abbrev, source_id);
CREATE INDEX GOAssociation_ind07 ON CBIL.GOAssociation(organism);
CREATE INDEX GOAssociation_ind08 ON CBIL.GOAssociation(taxon_id);

GRANT SELECT ON CBIL.GOAssociation TO comm_wdk_w, gus_r, gus_w;

/* count of genes per term */

DROP MATERIALIZED VIEW IF EXISTS CBIL.GOTerm;

CREATE MATERIALIZED VIEW CBIL.GOTerm AS (

SELECT ontology_term_id
, ontology
, ontology_abbrev
, go_term
, go_term_id
, taxon_id
, organism
, COUNT(DISTINCT source_id) AS num_annotated_genes
FROM CBIL.GOAssociation 
GROUP BY ontology_term_id, ontology, ontology_abbrev, go_term, go_term_id, taxon_id, organism
);

CREATE UNIQUE INDEX GOTerm_06 ON CBIL.GOTerm (organism, ontology_term_id, num_annotated_genes);
CREATE INDEX GOTerm_ind01 ON CBIL.GOTerm (go_term, ontology_term_id);
CREATE INDEX GOTerm_ind02 ON CBIL.GOTerm (go_term_id, ontology_term_id);
CREATE INDEX GOTerm_ind03 ON CBIL.GOTerm (ontology_abbrev, go_term_id, go_term, num_annotated_genes);
CREATE INDEX GOTerm_ind04 ON CBIL.GOTerm (organism);
CREATE INDEX GOTerm_ind05 ON CBIL.GOTerm (taxon_id);

GRANT SELECT ON CBIL.GOTerm TO comm_wdk_w, gus_r, gus_w;
