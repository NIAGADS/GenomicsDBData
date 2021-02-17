## LoadFeatureScoreFromCSV Plugin
## $Id: LoadFeatureScoreFromCSV.pm $

package GenomicsDBData::Load::Plugin::LoadFeatureScoreFromCSV;
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
		descr => 'comma separated list of one or more file names, path provided by --fileDir option',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),


       stringArg({name => 'fileDir',
		descr => 'directory containing files',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
		 }),


        stringArg({name => 'filePattern',
		descr => 'file pattern to match',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
		  }),
     
     stringArg({name => 'sourceId',
		descr => 'ProtocolAppNode source_id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({name => 'columnMap',
		descr => 'JSON string listing mapping of field names in CSV file (assuming header) to fields in FeatureScore, e.g. {fileField:dbField,...}',
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
  my $purposeBrief = 'Loads feature/score information from a CSV file';

  my $purpose = 'This plugin reads a CSV file and loads it into Results.FeatureScore';

  my $tablesAffected = [['Results::FeatureScore', 'Enters a row for each variant feature']];

  my $tablesDependedOn = [];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;
TODO: support characteristics

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2021. 
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

  my @files = $self->getFileList();
  for my $f (@files) {
    $self->load($f);
  }
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub getFileList {
  my ($self) = @_;

  my $pattern = $self->getArg('filePattern');

  my @files = ();
  if ($self->getArg('file')) {
    @files = split /,/, $self->getArg('file')
  }
  else {
    $self->error('Must supply filePattern if no file list provided') if (!$pattern);
    $self->log("Finding files in " . $self->getArg('fileDir') . " that match $pattern");
    opendir(my $dh, $self->getArg('fileDir')) || $self->error("Path does not exists: " . $self->getArg('fileDir'));
    @files = grep(/${pattern}/, readdir($dh));
    closedir($dh); 
  }
  $self->log("Found the following files: @files");
  return @files;
}


sub assembleFeature {
  my ($self, $data) = @_;

  my $columnMap = $self->{column_map};

  my $chr = $data->[$columnMap->{chromosome}];
  $self->error("Out of range chr found: $chr") if ($chr !~ m/M|MT|X|Y/ and $chr > 22);
  
  $chr = "chr" . $chr unless ($chr =~ /chr/);
  $chr =~ s/MT/M/;

  my $locStart = $data->[$columnMap->{location_start}] + 1; # bed files are zero-based
  my $locEnd = (exists $columnMap->{location_end}) ? $data->[$columnMap->{location_end}] : $locStart;

  my $result = {
		chromosome => $chr,
		location_start => $locStart,
		location_end => $locEnd};

  $result->{feature_name} = Utils::truncateStr($data->[$columnMap->{name}], 22)
    if (exists $columnMap->{name});
  $result->{strand} = $data->[$columnMap->{strand}] 
    if (exists $columnMap->{strand});
  $result->{score} = $data->[$columnMap->{score}]
    if (exists $columnMap->{score});

  $result->{position_cm} = $data->[$columnMap->{position_cm}]
    if (exists $columnMap->{position_cm});

  return $result;
}

sub buildColumnMap {
  my ($self, $header) = @_;

  my @fields = split /\t/, $header;
  my %fieldMap = map { $fields[$_] => $_ } 0..$#fields;
  
  my $json = JSON::XS->new;
  my $file2dbMap = $json->decode($self->getArg('columnMap')) || $self->error("Error parsing column mapping");
  
  my $columnMap = {};
  foreach my $fileField (keys %$file2dbMap) {
    my $dbColumn = $file2dbMap->{$fileField};
    $columnMap->{$dbColumn} = $fieldMap{$fileField};
  }
  $self->{column_map} = $columnMap;

}


sub load {
  my ($self, $fileName) = @_;

  my $filePath = $self->getArg('fileDir') . '/' . $fileName;

  my $protocolAppNodeId = PluginUtils::getProtocolAppNodeId($self, $self->getArg('sourceId'));
  open (my $fh, $filePath) || $self->error("Unable to open $filePath");

  # get indexes of field names
  my $header = <$fh>;
  chomp($header);
  $self->buildColumnMap($header);

  $self->log("Processing $filePath");
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
  my @tables = qw(Results.FeatureScore);
  return @tables;
}

1;
