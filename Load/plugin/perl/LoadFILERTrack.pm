## LoadFILERTrack Plugin
## $Id: LoadFILERTrack.pm $

package GenomicsDBData::Load::Plugin::LoadFILERTrack;
@ISA = qw(GUS::PluginMgr::Plugin);

use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);

use File::Slurp;
# use File::Fetch;

use LWP::UserAgent;
use HTTP::Request;
# use Gzip::Faster;

# use Compress::Zlib;

use IO::Uncompress::Gunzip;

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
     stringArg({name => 'annotationFile',
		descr => 'tab-delim annotation file detailing files and characteristics to be linked to the datasets, see NOTES',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     stringArg({name => 'filerUri',
		descr => 'Uri for FILER data requests',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),


     booleanArg({name => 'validateOntologyTerms',
		 descr => 'in non-commit mode; just process annotation to validate ontologyterms',
		 constraintFunc=> undef,
		 reqd  => 0,
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

     stringArg({name => 'fileDir',
		descr => 'The full path to the directory for temporary file storage.',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),


     stringArg({name => 'study',
		descr => 'study source id; ProtocolAppNode source_ids will be generated as studySourceId_datasetSourceId where datasetSourceId should be specified in the "SOURCE_ID" field of the annotation file',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),
     
     stringArg({name => 'track',
		descr => 'only load the specified track (identified by FILER_TRACK_ID)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({name => 'resumeAtDataset',
		descr => 'resume load at specific dataset (provide file name)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),


     stringArg({name => 'scoreLabel',
		descr => 'label for the score field, applied to all datasets listed in annotation file; if dataset specific provide "SCORE_LABEL"  field in the annotation file',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({name => 'scoreDescription',
		descr => 'description for the score field, applied to all datasets listed in annotation file; if dataset specific provide "SCORE_DESCRIPTION" field in the annotation file',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({name => 'trackSubType',
		descr => 'ontology term defining track type, applied to all datasets listed in annotation file; if dataset specific provide "TYPE" field in annotation file.  All dataset ProtocolAppNodes will be assigned "Functional genomics" as the type.  "TYPE" in the annotation file will be saved in the subtype for the ProtocolAppNode',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({name => 'technologyType',
		descr => 'technology type (ChIP-Seq, RNA-seq, etc); if dataset specific provide the "CHARACTERISTIC|technology type" field in the annotation file',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

  booleanArg({name => 'useScore',
		 descr => 'should the genome browser track use the score?',
		 constraintFunc=> undef,
		 reqd  => 0,
		 isList => 0,
		}),

     booleanArg({name => 'itemRgb',
		 descr => 'should the genome browser track use the Rgb fields?',
		 constraintFunc=> undef,
		 reqd  => 0,
		 isList => 0,
		}),

     enumArg({name => 'bedType',
	      descr => 'type of bed file, if not specified here must be specified in annotation file for each dataset in FILER_FILE_FORMAT field',
	      constraintFunc=> undef,
	      reqd  => 0,
	      isList => 0,
	      enum => "bed3, bed4, bed6, bed9, bed10, bed12, narrowPeak, broadPeak, gappedPeak, bedRnaElements, idr_peak, tss_peak, bed6+GTEX, bed6+DASHR"
	     }),

     

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for the ProtocolAppNodes. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                 constraintFunc => undef,
                 reqd           => 1,
                 isList         => 0 
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

Annotation file should be tab-delimited w/a (case-insensitive) header and least the following required columns:

FILE (file name, not full path)
SOURCE_ID (protocol_app_node source_id suffix (prefix will be study source_id)
NAME (protocol app node name)

Optional Columns include:

DESCRIPTION (protocol app node description)
TYPE (protocol app node subtype)
SCORE_LABEL (label for the score field)
SCORE_DESCRIPTION (description of the score field/displayable help)

Characteristics should be provided by fields named as:

CHARACTERISTIC|QUALIFIER

where "QUALIFIER" is a mappable ontology term (case Sensitive), eg.

CHARACTERISTIC|tissue
CHARACTERISTIC|technology type
CHARACTERISTIC|histone modification
CHARACTERISTIC|antibody target

field values may be terms (case sensitive) or ontology term source_ids (using _ instead of : to delineate the ontology from the ID)

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
		     cvsRevision => '$Revision: 14 $',
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

  $self->{type_id} = $self->getOntologyTermId($TYPE);
  $self->{subtype_id} =  $self->getOntologyTermId($TYPE) if ($self->getArg('trackSubType') );
  $self->{bed_field_key} = $self->parseBedFieldKey();
  

  my $annotation = $self->parseAnnotation();

  $self->log(Dumper($annotation)) if $self->getArg('veryVerbose');

  $self->loadDatasets($annotation);
  # $self->clean();

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


sub loadDatasets {
  my ($self, $annotation) = @_;
  while (my ($track, $properties)  = each %$annotation) {
    next if $track eq "dataset";
    $self->log("Processing dataset $track with the following annotation: " . Dumper($properties)) 
      if $self->getArg('veryVerbose');
    my $protocolAppNodeId = $self->loadProtocolAppNode($properties);
    if (!$self->getArg('validateOntologyTerms') or $self->getArg('commit')) {
      my $fileName = $self->getArg('filerUri') . "/" . $properties->{uri};
      $self->loadFeatureScores($fileName, $protocolAppNodeId, $properties);
    }
  }
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

sub parseAnnotation {
  my ($self) = @_;
  
  my $file = $self->getArg('annotationFile');
  my $study = $self->getArg('study');
  open(my $fh, $file) || $self->error("Unable to open: $file");
  my $header = <$fh>;
  my @fieldNames = split /\t/, $header;
  foreach my $i (0..$#fieldNames) {
    $fieldNames[$i] = lc($fieldNames[$i])
      if !($fieldNames[$i] =~ /CHARACTERISTIC/);
  }

  # $_ = lc for @fieldNames ;	# convert all to lower case except for characteristics
  
  my %columnMap = map { $fieldNames[$_] => $_ } 0..$#fieldNames;

  my $fileProps = {};
  my $foundStartPoint = 0;

  my $bedFileType = ($self->getArg('bedType')) ? $self->getArg('bedType') : undef;
  my $bedFields =  ($bedFileType) ? $self->getBedFields($self->getArg('bedType')) : undef;

  while (<$fh>) {
    chomp;
    my (@values) = split /\t/;
    my $trackId = $values[$columnMap{filer_track_id}];

    if ($self->getArg('track')) { # only extract info for this dataset
      next if (!($file =~ $self->getArg('track')));
    }

    if ($self->getArg('resumeAtDataset')) {
      next if (!($file =~ $self->getArg('resumeAtDataset')) and !$foundStartPoint);
      $foundStartPoint = 1; 
    }
  
    $fileProps->{$trackId} = {source_id => $trackId,
			   name => $values[$columnMap{name}]};


    $fileProps->{$trackId}->{description} = $values[$columnMap{description}] if (exists $columnMap{description});
    if (exists $self->{subtype_id}) {
      $fileProps->{$trackId}->{subtype_id} = $self->{subtype_id};
    } else {
      $fileProps->{$trackId}->{subtype_id} = $self->getOntologyTermId($values[$columnMap{type}]);
    }

    my $trackDisplay = {};
    $trackDisplay->{score_label} = $self->getArg('scoreLabel') if ($self->getArg('scoreLabel'));
    $trackDisplay->{score_label} = $values[$columnMap{score_label}] if (exists $columnMap{score_label});
    $trackDisplay->{score_description} = $self->getArg('scoreDescription') if ($self->getArg('scoreDescription'));
    $trackDisplay->{score_description} = $values[$columnMap{score_description}] if (exists $columnMap{score_description});
    $trackDisplay->{useScore} = 1 if ($self->getArg('useScore'));
    $trackDisplay->{itemRgb} = "on" if ($self->getArg('itemRgb'));

    $fileProps->{$trackId}->{track_display} = TO_JSON($trackDisplay) if (scalar keys %$trackDisplay > 0);
    $fileProps->{$trackId}->{characteristics} = $self->extractCharacteristics(\%columnMap, @values);

    if (!$bedFields) {
      $self->error("No BED 'FILER_FILE_FORMAT' found in annotation for file $file.  Must add to annotation file or specify (bed) file type (for all files) using the --bedType option.")
	if !(exists $columnMap{file_type});

      $fileProps->{$trackId}->{file_type} = $values[$columnMap{filer_file_format}];
      $fileProps->{$trackId}->{bed_fields} = $self->getBedFields($values[$columnMap{filer_file_format}]);
    }
    else {
      $fileProps->{$trackId}->{bed_fields} = $bedFields;
      $fileProps->{$trackId}->{file_type} = $bedFileType;
    }

    $fileProps->{$trackId}->{uri} = $values[$columnMap{filer_path}] . "/" . $fileProps->{$trackId}->{file_type} 
      . "/" . $values[$columnMap{filer_genome_build}] . "/" . $values[$columnMap{file}];

  }

  $fh->close();

  return $fileProps;
}

sub extractCharacteristics {
  my ($self, $columns, @values) = @_;

  my $chars = {};
  $chars->{"technology type"} = $self->getArg('technologyType') if ($self->getArg('technologyType'));
  
  while (my ($field, $index) = each %$columns) {
    if ($field =~ m/CHARACTERISTIC/) {
      my ($temp, $qualifier) = split /\|/, $field;
      $qualifier =~ s/\s+$//;
      my $term = $values[$index];
      if ($term) {
	$term = "value:" . $term if ($qualifier =~ m/FILE/g);
	$chars->{$qualifier} =  $term;
      }

    }
  }

  return $chars;
}

sub getFh {
  my ($self, $uri) = @_;

  my @tpath = split "/", $uri;
  my $targetFile = $self->getArg('fileDir') . '/' . $tpath[-1];

  $self->log("FETCHING $uri and saving to $targetFile.");
  my $ua = LWP::UserAgent->new();
  my $response = $ua->get($uri, ':content_file' => $targetFile);
  if ($response->is_success ()) {
    if ($response->header('Client-Aborted') ne 'die') {
      $self->log("UNCOMPRESSING $targetFile.");
      open(my $fh, "gunzip -c $targetFile |");
      return ($fh, $targetFile);
    }
    else {
      $self->log("FETCH ERROR: GET $uri failed.  Error Writing response to $targetFile.");
    }
  }
  else {
    $self->error("FETCH ERROR: GET $uri failed: " . $response->status_line);
  }
  return undef, undef;
}

sub loadFeatureScores {
  my ($self, $uri, $protocolAppNodeId, $properties) = @_;

  my ($fh, $tempFile) = $self->getFh($uri);

  my $lineCount = 0;

  $self->log("PROCESSING $tempFile.");
  while (<$fh>) {
    next if m/^track/;		# skip track lines
    chomp;
    my @values = split /\t/;
    my $featureData = $self->assembleFeature(\@values, $properties);
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
  $self->log("DONE. INSERTED $lineCount records from $uri.");
  $self->undefPointerCache();
  unlink($tempFile);
}

sub assembleFeature {
  my ($self, $data, $properties) = @_;

  my $bedColumnMap = $properties->{bed_fields};

  my $chr = $data->[$bedColumnMap->{chromosome}];
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



sub assembleDisplayJson {
  my ($self, $data, $properties) = @_;

  my $fileType = $properties->{file_type};
  return undef if  $fileType eq 'bed3' or $fileType eq "bed4" or $fileType eq "bed6";

  my $bedColumnMap = $properties->{bed_fields};

  my $displayInfo = {};
  while (my ($field, $index) = each %$bedColumnMap) {
    next if ($field eq 'chromosome');
    next if ($field eq 'locStart');
    next if ($field eq 'locEnd');
    next if ($field eq 'score');
    next if ($field eq 'strand');
    next if ($field eq 'name');
    $displayInfo->{$field} = $data->[$index];
  }

  return TO_JSON($displayInfo);
}


sub TO_JSON {
  my ($data) = @_;
  return JSON->new->utf8->allow_blessed->convert_blessed->encode($data);
}


sub getOntologyTermId {
  my ($self, $term) = @_;

  my $SQL="SELECT ontology_term_id FROM SRes.OntologyTerm WHERE name = ?";

  my $qh = $self->getQueryHandle()->prepare($SQL);
  $qh->execute($term);
  my ($ontologyTermId) = $qh->fetchrow_array();
  $qh->finish();

  if (!$ontologyTermId) {
    $SQL="SELECT ontology_term_id FROM SRes.OntologyTerm WHERE source_id = ?";
    $qh = $self->getQueryHandle()->prepare($SQL);
    $qh->execute($term);
    ($ontologyTermId) = $qh->fetchrow_array();
    $qh->finish();
  }

  $self->error("Term $term not found in SRes.OntologyTerm") if (!$ontologyTermId);

  return $ontologyTermId;
}

sub loadProtocolAppNode {
  my ($self, $properties) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $properties->{source_id}, external_database_release_id => $extDbRlsId});
  if ($protocolAppNode->retrieveFromDB()) {
    $self->log("Protocol App Node for " . $protocolAppNode->getSourceId() . " already exists.  Checking/Updating Characteristics.");
  } else {
    $protocolAppNode->setName($properties->{name});
    $protocolAppNode->setSubtypeId($properties->{subtype_id});
    $protocolAppNode->setTypeId($self->{type_id});
    $protocolAppNode->setUri($self->{uri});
    $protocolAppNode->setDescription($properties->{description}) if (exists $properties->{description});
    $protocolAppNode->setTrackDisplay($properties->{track_display}) if (exists $properties->{track_display});

    $protocolAppNode->submit() unless ($protocolAppNode->retrieveFromDB());

    $self->loadStudyLink($protocolAppNode->getProtocolAppNodeId())
      if ($self->getArg('study'));
  }

  $self->loadCharacteristics($protocolAppNode, $properties->{characteristics})
    if (exists $properties->{characteristics});

  $self->undefPointerCache();
  return $protocolAppNode->getProtocolAppNodeId();
}


sub loadStudyLink {
  my ($self, $protocolAppNodeId) = @_;

  my $study = GUS::Model::Study::Study
    ->new({source_id => $self->getArg('study')});
  $self->error("No study for " . $self->getArg('study') . " found in DB.")
    unless $study->retrieveFromDB();

  my $studyLink = GUS::Model::Study::StudyLink
    ->new({study_id => $study->getStudyId()});

  $studyLink->setProtocolAppNodeId($protocolAppNodeId);
  $studyLink->submit() unless ($studyLink->retrieveFromDB());
}


sub loadCharacteristics {
  my ($self, $protocolAppNode, $chars) = @_;

  my @terms = undef;
  while (my ($qualifier, $term) = each %$chars) {
    # $term may be an array
    if (ref($term) eq 'ARRAY') {
      $self->log("Found list of characteristics with same qualifier:" . Dumper($term));
      @terms = @$term;
    } else {
      @terms = ($term);
    }

    foreach my $t (@terms) {
      my $characteristic = GUS::Model::Study::Characteristic
	->new({qualifier_id => $self->getOntologyTermId($qualifier)});
      
      if ($t =~ m/^value:/) {
	$t =~ s/value://;
	$characteristic->setValue($t);
      } else {
	$characteristic->setOntologyTermId($self->getOntologyTermId($t));
      }
      
      $characteristic->setProtocolAppNodeId($protocolAppNode->getProtocolAppNodeId());
      $characteristic->submit() unless ($characteristic->retrieveFromDB());
    }
  }
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




# ----------------------------------------------------------------------
sub undoTables {
  my ($self) = @_;
  my @tables = qw(Study.StudyLink Study.Characteristic Results.FeatureScore Study.ProtocolAppNode);
  return @tables;
}

1;