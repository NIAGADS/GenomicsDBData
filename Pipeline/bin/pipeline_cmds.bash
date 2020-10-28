# Sequence Ontology

loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load xdbr --commit > $DATA_DIR/logs/load_sequence_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/sequence_ontology.json --load data --commit > $DATA_DIR/logs/load_sequence_ontology.log 2>&1

# Taxon

ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml --comment "ga GUS::Supported::Plugin::LoadGusXml --filename $GUS_HOME/lib/xml/sres/taxon.xml" --commit > $DATA_DIR/logs/load_taxon.log 2>&1

# Genome

loadResource --config $CONFIG_DIR/reference_databases/hg19_genome.json --load xdbr --commit > $DATA_DIR/logs/load_hg19_genome_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genome.json --load data --commit > $DATA_DIR/logs/load_hg19_genome.log 2>&1

# Genes

loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --load xdbr --commit > $DATA_DIR/logs/load_hg19_genes_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --preprocess  > $DATA_DIR/logs/load_hg19_genes_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/hg19_genes.json --load data  > $DATA_DIR/logs/load_hg19_genes.log 2>&1



# Niagads Ontology

loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_niagads_ontology_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --preprocess --verbose > $DATA_DIR/logs/load_niagads_ontology_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/niagads_ontology.json --load data --commit --verbose > $DATA_DIR/logs/load_niagads_ontology.log 2>&1

# EDAM

loadResource --config $CONFIG_DIR/ontologies/edam.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_edam_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/edam.json --load data --commit --verbose > $DATA_DIR/logs/load_edam.log 2>&1

# EFO

loadResource --config $CONFIG_DIR/ontologies/efo.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_efo_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/efo.json --load data --commit --verbose > $DATA_DIR/logs/load_efo.log 2>&1

# UBERON

loadResource --config $CONFIG_DIR/ontologies/uberon.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_uberon_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/uberon.json --load data --commit --verbose > $DATA_DIR/logs/load_uberon.log 2>&1

# CHEBI

loadResource --config $CONFIG_DIR/ontologies/chebi.json --load xdbr --commit --verbose > $DATA_DIR/logs/load_chebi_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/ontologies/chebi.json --load data --commit --verbose > $DATA_DIR/logs/load_chebi.log 2>&1

# DBSNP

loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load xdbr --commit > $DATA_DIR/logs/load_dbsnp_xdbr.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --preprocess > $DATA_DIR/logs/load_dbsnp_preprocess.log 2>&1
loadResource --config $CONFIG_DIR/reference_databases/dbsnp.json --load data --veryVerbose --commit > $DATA_DIR/logs/load_dbsnp.log 2>&1

