## LoadEnsemblMotifFeatures.pm
## $Id: LoadEnsemblMotifFeatures.pm $
##

package GenomicsDBData::Load::Plugin::LoadEnsemblMotifFeatures;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::Results::Motif;
use GUS::Model::SRes::Motif;

use JSON::XS;

use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my $COPY_SQL = <<COPYSQL;
COPY Results.Motif (
external_database_release_id,
chromosome,
location_start,
location_end,
strand,
-- bin_index, updated by trigger
motif_source_id,
matrix_id,
feature_type,
score,
annotation,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
COPYSQL

my $MATRICES = {};


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'fileDir',
		descr => 'directory containing per-chromosome files',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
                 mustExist => 1,
	       }),


     stringArg({name => 'file',
		descr => 'specific file',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
                 mustExist => 1,
	       }),

     integerArg({name => 'commitAfter',
		descr => 'commit after N rows',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
		default => 10000
	       }),

     stringArg({name => 'filePattern',
		descr => 'for file name <pattern usually species.genomebuild>.<chr>.motif_features.gff',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	   }),

     stringArg({name => 'chromosomes',
		descr => 'comma separated lists of chromosomes',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	   }),

     stringArg({name => 'schema',
		descr => 'specify sres or results',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	   }),

  stringArg({ name  => 'extDbRlsSpec',
                  descr => "The ExternalDBRelease specifier for the motifs. Must be in the format 'name|version', where the name must match an name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                  constraintFunc => undef,
                  reqd           => 1,
                  isList         => 0 }),


    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Ensembl Motifs table';

  my $purpose = 'This plugin loads the Ensembl Motifs';

  my $tablesAffected = [['Results::Motif', 'Enters a row for each motif']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

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
		     cvsRevision => '$Revision: 15 $',
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

  $self->{external_database_release_id} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  my $chrms = $self->getArg('chromosomes');
  my @chrmList = ($chrms) ? split /,/, $chrms : undef;
  my %chrmHash = (@chrmList) ?  map { $_ => 1 } @chrmList : undef;

  my $schema = lc($self->getArg('schema'));
  my @files = $self->getFiles();
  foreach my $f (@files) {
    $f =~ m/\.(\d+|MT)\./;
    my $chromosome = $1;
    $self->{chromosomse} = "chr$chromosome";
    if ($chrms) {
      if (exists $chrmHash{$chromosome}) {
	$self->loadResult($f) if ($schema eq "results");
	$self->loadSRes($f) if ($schema eq "sres");
      }
    }
    else {
      $self->loadResult($f) if ($schema eq "results");
      $self->loadSRes($f) if ($schema eq "sres");
    }
  }

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getFiles {
  my ($self) = @_;

  return ($self->getArg('file')) if ($self->getArg('file'));

  my $pattern = $self->getArg('filePattern');
  $self->log("Finding files in " . $self->getArg('fileDir') . " that match $pattern");
  opendir(my $dh, $self->getArg('fileDir')) || $self->error("Path does not exists: " . $self->getArg('fileDir'));
  my @files = grep(/${pattern}/, readdir($dh));
  closedir($dh);
  return @files;
}

sub loadResult {
  my ($self, $fileName) = @_;

  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);
  
  my $filePath = $self->getArg('fileDir') . '/' . $fileName;
  $self->log("Processing $filePath");
  open(my $fh, $filePath) || $self->error("Unable to open $filePath.");

  my @fields = qw(chrm spacer1 feature_type location_start location_end score strand spacer2 annotation);
  my $insertStrBuffer = "";
  my %row;
  my $count = 0;
  while(<$fh>) {
    chomp;
    my @values = split /\t/;
    @row{@fields} = @values;

    $insertStrBuffer .= $self->generateInsertStr(\%row);
    if (++$count % $self->getArg('commitAfter') == 0) {
      $self->log("Read $count result records; Performing Bulk Inserts");
      PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
      $insertStrBuffer = "";
    }
  }

  # residuals
  $self->log("Read $count result records; Performing Bulk Inserts");
  PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
  $insertStrBuffer = "";
  $fh->close();

}


sub loadSRes {
  my ($self, $fileName) = @_;

  my $filePath = $self->getArg('fileDir') . '/' . $fileName;
  $self->log("PROCESSING $fileName");
  open(my $fh, $filePath) || $self->error("Unable to open $filePath.");

  my @fields = qw(chrm spacer1 feature_type location_start location_end score strand spacer2 annotation);
  my %row;

  my $count = 0;
  my $matrixCount = 0;
  while(<$fh>) {
    chomp;
    my @values = split /\t/;
    @row{@fields} = @values;

    $matrixCount = $self->setMatrixValues($matrixCount, \%row);
    if (++$count % $self->getArg('commitAfter') == 0) {
      $self->log("READ $count lines; FOUND $matrixCount unique PWMs");
    }
  }
  $fh->close();
  $self->log("READ $count lines; FOUND $matrixCount unique PWMs");
  $self->log("DONE processing $fileName.");
  $self->loadMatrices();
}

sub loadMatrices {
  my ($self) = @_;
  my $count = 0;
  foreach my $matrixId (keys %$MATRICES) {
    my @sources = @{$MATRICES->{$matrixId}->{motif_source_id}};
    my $sources = "'{'" . join(',', @sources) . "'}'";
    $MATRICES->{$matrixId}->{motif_source_id} = $sources;

    my $motif = GUS::Model::SRes::Motif
      ->new($MATRICES->{$matrixId});

    $motif->submit() unless $motif->retrieveFromDB();
    if (++$count % 100 == 0) {
      $self->log("LOADED $count motifs");
      $self->undefPointerCache();
    }
  }
  $MATRICES = {};
}

sub setMatrixValues {
  my ($self, $count, $data) = @_;

  my $annotation = $self->generateAnnotationObj($data->{annotation});
  my $matrixId = $annotation->{binding_matrix_stable_id};
  my $sourceId = $annotation->{stable_id};

  if (!exists $MATRICES->{$matrixId}) {
    my $featureType = $data->{feature_type};
    $featureType =~ s/_/ /g;

    delete $annotation->{stable_id};
    delete $annotation->{binding_matrix_stable_id};
    my @sources = ($sourceId);

    my %values = (external_database_release_id => $self->{external_database_release_id},
		  matrix_id => $matrixId,
		  motif_source_id => \@sources,
		  feature_type => $featureType,
		  annotation => Utils::to_json($annotation),
		  chromosome => $self->{chromosome}
		 );

    $MATRICES->{$matrixId} = \%values;
    $count++;
  }

  my @sources = @{$MATRICES->{$matrixId}->{motif_source_id}};
  push(@sources, $sourceId);
  $MATRICES->{$matrixId}->{motif_source_id} = \@sources;

  return $count;
}

sub generateInsertStr {
  my ($self, $data) = @_;

#chrm spacer1 feature_type location_start location_end score strand spacer2 annotation);
# 1       .       TF_binding_site 10099   10118   2.729058868     +       .       binding_matrix_stable_id=ENSPFM0326;epigenomes_with_experimental_evidence=HepG2%2CIMR-90;stable_id=ENSM00907810587;transcription_factor_complex=HOXB2::RFX5
# 1       .       TF_binding_site 10100   10112   -25.7219096287  +       .       binding_matrix_stable_id=ENSPFM0014;epigenomes_with_experimental_evidence=K562%2CMCF-7;stable_id=ENSM00521948409;transcription_factor_complex=ATF4::CEBPB%2CATF4::CEBPD%2CATF4::TEF%2CATF4%2CCEBPG::ATF4

  my $featureType = $data->{feature_type};
  $featureType =~ s/_/ /g;

  my $chrmN = $data->{chrm} eq 'MT' ? 'M' : $data->{chrm};
  my $chrm = "chr$chrmN";

  my $annotation = $self->generateAnnotationObj($data->{annotation});
  my $sourceId = $annotation->{stable_id};
  my $matrixId = $annotation->{binding_matrix_stable_id};
  delete $annotation->{stable_id};
  delete $annotation->{binding_matrix_stable_id};

  my @values = ($self->{external_database_release_id},
		$chrm,
		$data->{location_start},
		$data->{location_end},
		$data->{strand},
		$sourceId,
		$matrixId,
		$featureType,
		$data->{score},
		Utils::to_json($annotation)
	       );

  push(@values, GenomicsDBData::Load::Utils::getCurrentTime());
  push(@values, $self->{housekeeping});
  my $str = join("|", @values);

  return "$str\n";
}

sub str2array {
  my ($self, $str) = @_;
  my @values = split /%2C/, $str;
  return \@values;
}

sub generateAnnotationObj {
  my ($self, $annotationStr) = @_;
  my %annotation = split /[;=]/, $annotationStr;
  # transcription_factor_complex
  # epigenomes_with_experimental_evidence
  $annotation{transcription_factor_complex} = $self->str2array($annotation{transcription_factor_complex})
    if (exists $annotation{transcription_factor_complex});
  $annotation{epigenomes_with_experimental_evidence} = $self->str2array($annotation{epigenomes_with_experimental_evidence})
    if (exists $annotation{epigenomes_with_experimental_evidence});

  return \%annotation;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  return ('SRes.Motif'); # too many rows for Results.Motif

}



1;
