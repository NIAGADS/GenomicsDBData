-- set categories for ontology terms mapped to genome-browser tracks
update sres.OntologyTerm
set category = 'antibody target'
where source_id in ('PR_000005997', 'PR_000007278', 'PR_000008421', 'PR_000007644', 
                    'PR_000013894', 'PR_000016014', 'PR_000007858', 'PR_000001941', 
                    'PR_000013667', 'PR_000017137', 'PR_000017553', 'PR_000007102', 
                    'PR_000014877', 'PR_000012987', 'H3K4me2', 'H3K36me3', 'H3K79me2', 
                    'H3K9ac', 'H3K9me3', 'H4K20me1');

update sres.OntologyTerm
set category = 'histone modification'
where source_id in ('CHEBI_85044', 'CHEBI_85045', 'CHEBI_85042', 'CHEBI_85043');

update sres.OntologyTerm
set category = 'cell line'
where source_id in ('CLO_0001915', 'CLO_0008425', 'CLO_0009059', 'CLO_0009058', 'CLO_0009464', 
                    'Gliobla', 'Ha-h', 'HA-sp', 'HBMEC', 'Medullo', 'NH-A', 'SH-SY5Y', 
                    'SK-N-SH_RA', 'BTO_0001620', 'NO_0000033', 'BTO_0000793', 'EFO_0005234','NO_0000035', 'BTO_0002036', 'NO_0000034', 'EFO_0002802');

UPDATE sres.OntologyTerm SET category = 'tissue'
WHERE source_id IN ('UBERON_0000955', 'UBERON_0002240', 'EFO_0000530');

UPDATE SRes.ONtologyTerm SET category = 'cell'
WHERE source_id IN ('BTO_0000099', 'EFO_0000621', 'EFO_0002782','CL_0000540','EFO_0002939', 'BTO_0000527','BTO_0003636','CL_0000127' ,'CL_0000047');

-- count category assignments
select count(*), category
from sres.OntologyTerm ot, study.characteristic c
where ot.ontology_term_id = c.ontology_term_id
group by category;

-- list assigned ontology terms with no category
select DISTINCT source_id, name, definition
from sres.OntologyTerm ot, study.characteristic c
where ot.ontology_term_id = c.ontology_term_id
and category is null;
