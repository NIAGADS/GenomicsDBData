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

my $TYPE = "Functional genomics";
my $SUBTYPES = { histone => "histone_modification",
		 enhancer => "enhancer",
		 "protein peaks" => "transcription factor binding site",
		 "TSS" => "regulation of transcription, start site selection",
		 "transcription start sites" => "regulation of transcription, start site selection",
		 "DNase" => "DNAse hypersensitive region"
	       };

my $QUALIFIERS = {
		  Assay => "sequencing assay",
		  "Genomic feature" => "Sequence feature type",
		  "Tissue category" => "FILER_TISSUE_CATEGORY",
		  "Cell type" => "cell type"
		 };
#{
#"type" : "bed",
#"name" : "ENCODE ENCFF059DTX.bed.gz",
#"showOnHubLoad" : "true",
#"url" : "https://tf.lisanwanglab.org/GADB/Annotationtracks/ENCODE/data/ChIP-seq/narrowpeak/hg19/1/ENCFF059DTX.bed.gz",
#"metadata" : { "Data source" : "ENCODE", "Assay" : "ChIP-seq", "Genomic feature" : "ChIP-seq H3K27ac-histone-mark peaks", "Tis#sue category" : "Male Reproductive", "Cell type" : "22Rv1", "Long name" : "ENCODE 22Rv1 [Male Reproductive] ChIP-seq H3K27ac-h#istone-mark peaks ENCFF059DTX.bed.gz" }
#},#

  


# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     fileArg({name => 'trackHub',
	      descr => 'FILER track hub',
	      constraintFunc=> undef,
	      reqd  => 1,
	      isList => 0,
	      type=>'JSON',
	      mustExist=>1
	       }),

     stringArg({name => 'filerUri',
		descr => 'Uri for FILER data requests',
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

     stringArg({name => 'fileDir',
		descr => 'The full path to the directory for temporary file storage.',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),


     
     fileArg({name => 'skip',
	      descr => 'full path to newline separated list of tracks to skip',
	      constraintFunc=> undef,
	      reqd  => 0,
	      isList => 0,
	      mustExist => 1,
	      format => "TXT"
	     }),


     booleanArg({name => 'logCompletedTracks',
	  descr => 'logs completed tracks; can be used as a "skip" file',
	      constraintFunc=> undef,
	      reqd  => 0,
	      isList => 0,
	     }),


     stringArg({name => 'tracks',
		descr => 'only load the specified tracks; specify as json object of fields, patterns e.g., {track:trackId, category:<>, datasource<>}, etc.',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

      stringArg({name => '',
		descr => 'only load the specified track (identified by FILER_TRACK_ID)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     booleanArg({name => 'loadTrackMetadata',
		descr => 'only load track metadata (protocolappnode placeholders)', 
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
		}),

      booleanArg({name => 'loadTracks',
		descr => 'load tracks; must specify --track option to limit to specific tracks',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({ name  => 'extDbRlsSpec',
                 descr => "The ExternalDBRelease specifier for FILER. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
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
		     cvsRevision => '$Revision: 18 $',
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

  my $trackHub = $self->parseTrackHub();
  $self->log(Dumper($trackHub)) if $self->getArg('veryVerbose');

  if ($self->getArg('logCompletedTracks')) {
    my $trackLogFile = $self->getArg('fileDir') . '/completed-tracks.log';
    open(my $fh, '>', $trackLogFile) || $self->error("Unable to create track log file: $trackLogFile");
    $self->{track_log_fh} = $fh;
  }

  $self->loadSkips() if ($self->getArg('skip'));

  $self->createPlaceholders($trackHub) if $self->getArg('loadTrackMetaData');
  # $self->loadDatasets($trackHub);
  $self->{track_log_fh}->close() if exists ($self->{track_log_fh});
  # $self->clean();

}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub loadSkips {
  my ($self) = @_;
  open(my $fh, $self->getArg('skip')) || $self->error("Unable to open skip file:" . $self->getArg('skip'));
  my $skips = {};
  while(my $line = <$fh>) {
    chomp $line;
    $skips->{$line} = 1;
  }
  $self->{skips} = $skips;
}

sub parseBedFieldKey {
  my ($self) = @_;
  my $file = $self->getArg('bedFieldKey');

  my $fileC = read_file($file);

  my $json = JSON::XS->new;  
  my $fieldKey = $json->decode($fileC) || $self->error("Error decoding JSON: $fileC");

  return $fieldKey;
}


# {
# "type" : "bed",
# "name" : "ENCODE ENCFF000NAW.bed.gz",
# "url" : "https://tf.lisanwanglab.org/GADB/Annotationtracks/ENCODE/data/ChIP-seq/broadpeak/hg19/ENCFF000NAW.bed.gz",
# "metadata" : { "Data source" : "ENCODE", "Assay" : "ChIP-seq", "Genomic feature" : "ChIP-seq protein peaks", "Tissue category" :

sub createPlaceholders {
  my ($self, $trackHub) = @_;
  my $logTracks = $self->getArg('logCompletedTracks');
  my $lfh = $self->{track_log_fh};

  foreach my $track (@$trackHub) {
    next if $track eq "dataset";
    $self->log("Processing dataset $track with the following annotation: " . Dumper($properties)) 
      if $self->getArg('veryVerbose');


    my $protocolAppNodeId = $self->loadProtocolAppNode($properties);
    if (!$self->getArg('validateOntologyTerms') or $self->getArg('commit')) {
      my $fileName = $self->getArg('filerUri') . "/" . $properties->{uri};
      
      if (defined $skips) {
	if (exists $skips->{$track}) {
	  $self->log("SKIPPING: $track / $fileName");
	  next;
	}
      }
      
      if ($logTracks) {
	print $lfh "$track\n";
      }
    }
  }
}


sub loadDatasets {
  my ($self, $annotation) = @_;
  my $logTracks = $self->getArg('logCompletedTracks');
  my $lfh = $self->{track_log_fh};
  my $skips = (exists $self->{skips}) ? $self->{skips} : undef;

  while (my ($track, $properties)  = each %$annotation) {
    next if $track eq "dataset";
    $self->log("Processing dataset $track with the following annotation: " . Dumper($properties)) 
      if $self->getArg('veryVerbose');


    my $protocolAppNodeId = $self->loadProtocolAppNode($properties);
    if (!$self->getArg('validateOntologyTerms') or $self->getArg('commit')) {
      my $fileName = $self->getArg('filerUri') . "/" . $properties->{uri};
      
      if (defined $skips) {
	if (exists $skips->{$track}) {
	  $self->log("SKIPPING: $track / $fileName");
	  next;
	}
      }
      
      $self->loadFeatureScores($fileName, $protocolAppNodeId, $properties);
      if ($logTracks) {
	print $lfh "$track\n";
      }
    }
  }
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

 "Lung", "Cell type" : "A549", "Long name" : "ENCODE A549 [Lung] ChIP-seq protein peaks ENCFF000NAW.bed.gz" }

sub parseTrackHub {
  my ($self) = @_;
  
  my $file = $self->getArg('trackHub');
  my $fileText = read_file($file) || $self->error("Unable to read track hub: $file");
  
  my $json = JSON::XS->new;
  my $trackHub = $json->decode() || $self->error("Error parsing track hub JSON");

  $self->{track_hub} = $trackHub;
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
    $protocolAppNode->setUri($properties->{uri});
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
