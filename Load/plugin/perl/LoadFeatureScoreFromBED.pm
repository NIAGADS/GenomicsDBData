## LoadFeatureScoreFromBED Plugin
## $Id: LoadFeatureScoreFromBED.pm $

package GenomicsDBData::Load::Plugin::LoadFeatureScoreFromBED;
@ISA = qw(GUS::PluginMgr::Plugin);

use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);

use File::Slurp;

use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';
use Package::Alias Utils => 'GenomicsDBData::Load::Utils';

use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::Characteristic;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Results::FeatureScore;

my $TYPE="Functional genomics";

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
  
     stringArg({name => 'file',
		descr => 'full path to BED file',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     fileArg({name => 'bedFieldKey',
		descr => 'JSON file containing mapping of bed file types to expected fields (full path)',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	      mustExist => 1,
	      format => "JSON"
	       }),

     fileArg({name => 'skip',
	      descr => 'full path to newline separated list of tracks to skip',
	      constraintFunc=> undef,
	      reqd  => 0,
	      isList => 0,
	      mustExist => 1,
	      format => "TXT"
	     }),


     stringArg({name => 'sourceId',
		descr => 'ProtocolAppNode source_id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

 

     enumArg({name => 'bedType',
	      descr => 'type of bed file',
	      constraintFunc=> undef,
	      reqd  => 0,
	      isList => 0,
	      enum => "bed3, bed4, bed6, bed9, bed10, bed12, narrowPeak, broadPeak, gappedPeak, bedRnaElements, idr_peak, tss_peak, bed6+GTEX, bed6+DASHR"
	     }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads feature/score information from a BED file';

  my $purpose = 'This plugin reads a bed file and loads it into Results.FeatureScore';

  my $tablesAffected = [['Results::FeatureScore', 'Enters a row for each variant feature']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
TODO: support characteristics

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2019. 
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
  my $argumentDeclaration = &getArgumentsDeclaration();

  $self->initialize({requiredDbVersion => 4.0,
		     cvsRevision => '$Revision: 20 $',
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

  $self->{bed_field_key} = $self->parseBedFieldKey();

  $self->load();
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------


sub parseBedFieldKey {
  my ($self) = @_;
  my $file = $self->getArg('bedFieldKey');

  my $fileC = read_file($file);

  my $json = JSON::XS->new;  
  my $fieldKey = $json->decode($fileC) || $self->error("Error decoding JSON: $fileC");

  return $fieldKey;
}


sub getBedFields {
  my ($self, $bedFileType)  = @_;

  my $bfKey = $self->{bed_field_key};
  $self->error("BED file type: $bedFileType not found in field map:" . Dumper($bfKey))
    if (!exists $bfKey->{$bedFileType});
  
  my $bfStr = $bfKey->{$bedFileType};
  my @bedFieldNames = split /;/, $bfStr;
  my %bedColumnMap = map { $bedFieldNames[$_] => $_ } 0..$#bedFieldNames;  
  return \%bedColumnMap;
}


sub assembleFeature {
  my ($self, $data) = @_;

  my $bedColumnMap = $self->getBedFields($self->getArg('bedType'));

  my $chr = $data->[$bedColumnMap->{chromosome}];
  $self->error("Out of range chr foudn: $chr") if ($chr !~ m/M|MT|X|Y/ and $chr > 22);
  
  $chr = "chr" . $chr unless ($chr =~ /chr/);
  $chr =~ s/MT/M/;

  my $locStart = $data->[$bedColumnMap->{locStart}] + 1; # bed files are zero-based
  my $locEnd = $data->[$bedColumnMap->{locEnd}];

  my $result = {
		chromosome => $chr,
		location_start => $locStart,
		location_end => $locEnd};

  $result->{feature_name} = Utils::truncateStr($data->[$bedColumnMap->{name}], 22)
    if (exists $bedColumnMap->{name});
  $result->{strand} = $data->[$bedColumnMap->{strand}] 
    if (exists $bedColumnMap->{strand});
  $result->{score} = $data->[$bedColumnMap->{score}]
    if (exists $bedColumnMap->{score});

  return $result;
}


sub load {
  my ($self) = @_;

  my $protocolAppNodeId = PluginUtils::getProtocolAppNodeId($self, $self->getArg('sourceId'));
  open (my $fh, $self->getArg('file')) || $self->error("Unable to open " . $self->getArg('file'));

  my $lineCount = 0;
  while (<$fh>) {
    chomp;
    my @values = split /\t/;
    my $featureData = $self->assembleFeature(\@values);
    my $featureScore = GUS::Model::Results::FeatureScore
      ->new($featureData);

    $featureScore->setProtocolAppNodeId($protocolAppNodeId);

    $featureScore->submit();

    if (++$lineCount % 50000 == 0) {
      $self->log("INSERTED $lineCount records.");
      $self->undefPointerCache();
    }
  }
  $fh->close();
  $self->log("DONE. INSERTED $lineCount records.");
  $self->undefPointerCache();
}

# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  my @tables = qw(Study.StudyLink Study.Characteristic Results.FeatureScore Study.ProtocolAppNode);
  return @tables;
}

1;
