## LoadPopulations.pm
## $Id: LoadPopulations.pm $
##

package GenomicsDBData::Load::Plugin::LoadPopulations;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::SRes::OntologyTerm;
use GUS::Model::NIAGADS::Population;

use Encode;
use File::Slurp;
use JSON::XS;


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'input',
		descr => 'file containing population info in JSON format; see USAGE NOTES',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Populates Population table';

  my $purpose = 'This plugin loads the NIAGADS.Population table';

  my $tablesAffected = [['NIAGADS::Population', 'Enters a row for each population']];

  my $tablesDependedOn = [['SRes::OntologyTerm', 'for mapping populations']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
JSON config file format:
[
 {"source": "gnomAD", "source_id": "gnomad_sas", "abbrev": "SAS", "ontology_term": "HANCESTRO_0006"},
 {"source": "1000Genomes", "source_id": "gmaf", "abbrev": "GAF", "value": "Global", "description":"global allele frequency calculated as the allele count (AC) divided by the chromosome count (AN) across the 1000 Genomes super populations"},
 {"source": "gnomAD", "source_id": "gnomad_ami", "abbrev": "AMI", "value": "Amish"}
]

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2020. 
NOTES

  my $documentation = {purpose=>$purpose, purposeBrief=>$purposeBrief, tablesAffected=>$tablesAffected, tablesDependedOn=>$tablesDependedOn, howToRestart=>$howToRestart, failureCases=>$failureCases, notes=>$notes};

  return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
  my ($class) = @_;
  my $self = {};
  bless($self,$class);


  my $documentation = &getDocumentation();
  my $argumentDeclaration    = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision: 3 $',
		     name => ref($self),
		     revisionNotes => '',
		     argsDeclaration => $argumentDeclaration,
		     documentation => $documentation
		    });
  return $self;
}

# ----------------------------------------------------------------------
# run method to do the work
# ----------------------------------------------------------------------

sub run {
  my ($self) = @_;

  $self->logAlgInvocationId();
  $self->logCommit();
  $self->logArgs();
  $self->getAlgInvocation()->setMaximumNumberOfObjects(100000);

  $self->load();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub load {
  my ($self) = @_;
  my @populations = $self->parseInput();
  foreach my $pop (@populations) {
    # $self->log(Dumper($pop));
    my $ontologyTerm = (exists $pop->{ontology_term}) ? $self->getOntologyTerm($pop->{ontology_term}) : undef;
    my $popObj = GUS::Model::NIAGADS::Population
      ->new({abbreviation => $pop->{abbrev},
	     display_value => (exists $pop->{value}) ? $pop->{value} : $ontologyTerm->getName(),
	     datasource => $pop->{source},
	     source_id => $pop->{source_id},
	    });
    $popObj->setOntologyTermId($ontologyTerm->getOntologyTermId()) if (exists $pop->{ontology_term});
    $popObj->setDescription($pop->{description}) if (exists $pop->{description});
    $popObj->submit() unless $popObj->retrieveFromDB();
  }
}

sub getOntologyTerm {
  my ($self, $term) = @_;
  my $ontologyTerm = GUS::Model::SRes::OntologyTerm
    ->new({source_id => $term});
  $self->log("Unable to find ontology term for $term") unless ($ontologyTerm->retrieveFromDB());
  return $ontologyTerm;
}

sub parseInput {
  my ($self) = @_;
  my $file = $self->getArg('input');
  my $json = read_file $file, { binmode => ':utf8' };
  my $eJson = Encode::encode 'utf8', $json;
  my $populations = decode_json $eJson || $self->error("Error decoding JSON input file: $file");
  return @$populations;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('NIAGADS.Population');
}



1;
