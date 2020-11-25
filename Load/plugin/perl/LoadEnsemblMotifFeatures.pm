## LoadEnsemblMotifFeatures.pm
## $Id: LoadEnsemblMotifFeatures.pm $
##

package GenomicsDBData::Load::Plugin::LoadEnsemblMotifFeatures;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use Data::Dumper;

use GUS::Model::Results::Motif;

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

     stringArg({name => 'filePattern',
		descr => 'for file name <pattern usually species.genomebuild>.<chr>.motif_features.gff',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
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
		     cvsRevision => '$Revision: 1 $',
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

  $self->{extDbRlsId} = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  my @files = $self->getFiles();
  for my $f (@files) {
    $self->load($f);
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

sub load {
  my ($self, $fileName) = @_;

  $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);
  
  my $filePath = $self->getArg('fileDir') + '/' + $fileName;
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
    if (++$count % 50000 == 0) {
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


sub generateInsertStr {
  my ($self, $data) = @_;

#chrm spacer1 feature_type location_start location_end score strand spacer2 annotation);
# 1       .       TF_binding_site 10099   10118   2.729058868     +       .       binding_matrix_stable_id=ENSPFM0326;epigenomes_with_experimental_evidence=HepG2%2CIMR-90;stable_id=ENSM00907810587;transcription_factor_complex=HOXB2::RFX5
# 1       .       TF_binding_site 10100   10112   -25.7219096287  +       .       binding_matrix_stable_id=ENSPFM0014;epigenomes_with_experimental_evidence=K562%2CMCF-7;stable_id=ENSM00521948409;transcription_factor_complex=ATF4::CEBPB%2CATF4::CEBPD%2CATF4::TEF%2CATF4%2CCEBPG::ATF4

  my $annotation = generateAnnotationObj($data->{annotation});
  my $featureType = $data->{feature_type};
  $featureType =~ s/_/ /g;
  my @values = ($self->{external_database_release_id},
		'chr' . $data->{chrm} eq 'MT' ? 'M' : $data->{chrm},
		$data->{location_start},
		$data->{location_end},
		$annotation->{stable_id},
		$annotation->{binding_matrix_stable_id},
		$featureType,
		$data->{score},
		Utils::to_json($annotation)
	       );

  push(@values, GenomicsDBData::Load::Utils::getCurrentTime());
  push(@values, $self->{housekeeping});
  my $str = join("|", @values);
  return "$str\n";
}

sub generateAnnotationObj {
  my ($self, $annotationStr) = @_;
  my %annotation = split /[;=]/, $annotationStr;
  foreach my $label (keys %annotation) {
    $annotation{$label} = split /%/, $annotation{$label} if ($annotation{$label} =~ /%/);
  }
  return \%annotation;
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;

  #return ('Results.Motif');
  return (); # too many rows to undo 
}



1;
