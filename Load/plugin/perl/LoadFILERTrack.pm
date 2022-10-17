## LoadFILERTrack Plugin
## $Id: LoadFILERTrack.pm $

package GenomicsDBData::Load::Plugin::LoadFILERTrack;
@ISA = qw(GUS::PluginMgr::Plugin);

use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use POSIX qw(strftime);

use List::MoreUtils qw(uniq);
use String::CamelCase qw(decamelize);

use File::Slurp;
# use File::Fetch;

use URI;
use LWP::UserAgent;
use HTTP::Request;
# use Gzip::Faster;

# use Compress::Zlib;

use IO::Uncompress::Gunzip;

use Package::Alias Utils => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

use GUS::Model::Study::Study;
use GUS::Model::Study::StudyLink;
use GUS::Model::Study::Characteristic;
use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Results::FeatureScore;

my $SKIP_COUNT = 0;

my $DEBUG = {
	     ASSAYS => {},
	     CATEGORIES => {},
	     CLASSIFICATIONS => {},
	     CELL_LINES => {},
	     TYPES => {},
	     TISSUES => {},
	     SYSTEMS => {},
	     CANCER => {},
	     INVALID_TERMS => { TISSUES => {}, BIOSAMPLES => {}, SYSTEMS => {}},
	     PARSED_BIOSAMPLES => {},
	     NS_ONTOLOGIES => {},
	     TRACK_NAMES => {},
	    };
my $TYPE = "Functional genomics";

my $BIOSAMPLE_TERM_MAPPINGS = {
			       "cell line" => "cell line cell",
			       "Placental" => "Female Reproductive",
			       "Lymphatic" => "lymphoid system",
			       "Integumentary" => "integumental system"
			      };

my $BTO_TERM_MAPPINGS = {
			 "Skin" => "UBERON:0002097",
			 # "Muscular" => "UBERON:0000383",
			 "Bone" => "UBERON:0002481",
			 # "Skeletal Muscle" => "UBERON:0014892",
			 # "Muscle" => "UBERON:0002385",
			 "Urinary" => "UBERON:0001008"
			};

my $SUBTYPES = { histone => "histone_modification",
		 enhancer => "enhancer",
		 "ChIP-seq consolidated ChromHMM_enhancer" => "enhancer",
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

     stringArg({name => 'filerUri',
		descr => 'Uri for FILER data requests',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0,
	       }),

     fileArg({name => 'bedFieldKey',
		descr => 'JSON file containing mapping of bed file types to expected fields (full path)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	      mustExist => 0,
	      format => "JSON"
	       }),

     stringArg({name => 'fileDir',
		descr => 'The full path to the directory for temporary file storage.',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

      stringArg({name => 'genomeBuild',
		descr => 'genome build',
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

      stringArg({name => 'trackID',
		descr => 'only load the specified track (identified by FILER_TRACK_ID)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0,
	       }),

     stringArg({name => 'dataSource',
		descr => 'track data asource',
		constraintFunc=> undef,
		reqd  => 1,
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
		     cvsRevision => '$Revision: 22 $',
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
  # $self->{subtype_id} =  $self->getOntologyTermId($TYPE) if ($self->getArg('trackSubType') );
  # $self->{bed_field_key} = $self->parseBedFieldKey();

  $self->fetchTrackHub();

  

  my $logDir = PluginUtils::createDirectory($self,  $self->getArg('fileDir'),$self->getArg('dataSource'));
  $self->{completed_tracks} = [];

  
  # if ($self->getArg('logCompletedTracks')) {
  #   $self->error("Must supply fileDir to log tracks") if (!$self->getArg('fileDir'));
  #   my $trackLogFile = $self->getArg('fileDir') . '/' . $self->getArg('dataSource') . '-tracks';
  #   if ($self->getArg('loadTrackMetadata')) {
  #     $trackLogFile .= ".json";
  #     $self->{completed_tracks} = [];
  #   }
  #   else {
  #     $trackLogFile .= ".log";
  #   }

  #   open(my $fh, '>', $trackLogFile) || $self->error("Unable to create track log file: $trackLogFile");
  #   $self->{track_log_fh} = $fh;
  # }

  $self->loadSkips() if ($self->getArg('skip'));

  $self->createPlaceholders() if $self->getArg('loadTrackMetadata');
  # $self->loadDatasets($trackHub);
  # $self->clean();

  $self->log("NUM SKIPPED TRACKS = $SKIP_COUNT");
  $self->log("Generating DEBUG Reports");

  my @reports = qw(assays categories classifications cell_lines tissues systems cancer invalid_terms track_names ns_ontologies);
  foreach my $r (@reports) {

    if ($r =~ m/assays|categories|classifications/) {
      open(my $fh, '>', $logDir . "/" . $r . ".log") || $self->error("Unable to create log file for $r");
      print $fh join("\n", sort (keys %{$DEBUG->{uc($r)}})) . "\n";
      $fh->close();
    }
    else {
      if (keys %{$DEBUG->{uc($r)}}) {
	open(my $fh, '>', $logDir . "/" . $r . ".json") || $self->error("Unable to create log file for $r");
	print $fh Utils::to_json($DEBUG->{uc($r)}, 1) . "\n"; # 1-> pretty print
	$fh->close();
      }
    }
  }

 #  $self->log("DEBUG Cell Lines: " . ((keys %$DEBUG->CELL_LINES) ? Utils::to_json($DEBUG->CELL_LINES) : "None"));

  if ($self->getArg('loadTrackMetadata') && $self->getArg('logCompletedTracks')) {
    open(my $fh, '>', $logDir . "/updated-track-metadata.json") || $self->error("Unable to create log file for updated tracks");
    my @cTracks = @{$self->{completed_tracks}};
    print $fh "[" . join(',', @cTracks) . "]\n";
    $fh->close();
  }


  $self->{track_log_fh}->close() if exists ($self->{track_log_fh});
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


sub createPlaceholders {
  my ($self) = @_;
  my $trackHub = $self->{track_hub};
  my $logTracks = $self->getArg('logCompletedTracks');
  my $lfh = $self->{track_log_fh};

  foreach my $track (@$trackHub) {
    $self->log("Processing dataset $track with the following annotation: " . Dumper($track)) 
      if $self->getArg('veryVerbose');

    my $protocolAppNodeId = $self->loadProtocolAppNode($track);
    
    if ($logTracks) {
      # print $lfh "$track\n";
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
	  $self->log("SKIPPING: $track / $fileName") if $self->getArg('veryVerbose');
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

#  "Lung", "Cell type" : "A549", "Long name" : "ENCODE A549 [Lung] ChIP-seq protein peaks ENCFF000NAW.bed.gz" }

sub parseTrackHub {
  my ($self) = @_;
  
  my $file = $self->getArg('trackHub');
  my $fileText = read_file($file) || $self->error("Unable to read track hub: $file");
  

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


sub fetchTrackHub {
  my ($self) = @_;
  
  my $requestUrl = $self->getArg('filerUri') . "/get_metadata.php";
  my %params = (genomeBuild => $self->getArg('genomeBuild'),
		filterString => '."Data Source"=="' . $self->getArg('dataSource') . '"');


  $self->log("FETCHING metadata from $requestUrl with parameters: " . Dumper(\%params));
  my $ua = LWP::UserAgent->new();
  $ua->ssl_opts(verify_hostname => 0); # filer certificate is often bad
  my $uri = URI->new($requestUrl);
  $uri->query_form(%params);
  my $response = $ua->get($uri);
  if ($response->is_success ()) {
      my $json = JSON::XS->new;
      my $trackHub = $json->decode($response->content) || $self->error("Error parsing track hub JSON: $!");
      $self->{track_hub} = $trackHub;
      $self->log("DONE: Fetched metadata for " . scalar @$trackHub . " tracks.");
      $self->log(Dumper($self->{track_hub})) if $self->getArg('veryVerbose');
    }

  else {
    $self->error("FETCH ERROR: GET $uri failed: " . $response->status_line);
  }

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

  return Utils::to_json($displayInfo);
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


  # {
  #   "Identifier": "NGFA001954",
  #   "Data Source": "FANTOM5_Enhancers",
  #   "File name": "CL:0000047_neuronal_stem_cell_expressed_enhancers.bed.gz",
  #   "Number of intervals": 785,
  #   "bp covered": 208182,
  #   "Output type": "Enhancer peaks",
  #   "Genome build": "hg19",
  #   "cell type": "Neuronal stem cell",
  #   "Biosample type": "cell",
  #   "Biosamples term id": "CL:0000047",
  #   "Tissue category": "Stem Cell",
  #   "ENCODE Experiment id": "Not applicable",
  #   "Biological replicate(s)": "Not applicable",
  #   "Technical replicate": "Not applicable",
  #   "Antibody": "Not applicable",
  #   "Assay": "CAGE-Seq",
  #   "File format": "bed bed12",
  #   "File size": 22137,
  #   "Downloaded date": "8/9/2018",
  #   "Release date": "4/19/2012",
  #   "Date added to FILER": "8/10/2018",
  #   "Processed File Download URL": "https://tf.lisanwanglab.org/GADB/Annotationtracks/FANTOM5/latest/basic/enhancers/bed12/hg19/CL:0000047_neuronal_stem_cell_expressed_enhancers.bed.gz",
  #   "Processed file md5": "4adff3e0e05573f771d1aa3bf405375d",
  #   "Link out URL": "http://slidebase.binf.ku.dk/",
  #   "Data Category": "Called peaks",
  #   "classification": "CAGE-Seq Enhancer peaks",
  #   "original cell type name": "neuronal stem cell",
  #   "system category": "Stem Cell",
  #   "trackName": "FANTOM5_Enhancers Neuronal stem cell CAGE-Seq Enhancer peaks",
  #   "tabixFileUrl": "https://tf.lisanwanglab.org/GADB/Annotationtracks/FANTOM5/latest/basic/enhancers/bed12/hg19/CL:0000047_neuronal_stem_cell_expressed_enhancers.bed.gz.tbi"
  # },


sub loadProtocolAppNode {
  my ($self, $track) = @_;

  my $extDbRlsId = $self->getExtDbRlsId($self->getArg('extDbRlsSpec'));

  my $sourceId = (exists $track->{Identifier}) ? $track->{Identifier} : $track->{"#Identifier"};
  
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $sourceId, external_database_release_id => $extDbRlsId});
  
  if ($protocolAppNode->retrieveFromDB()) {
    $self->error("SKIPPING:Protocol App Node for " . $protocolAppNode->getSourceId() . " already exists.");
  }

  $DEBUG->{ASSAYS}->{$track->{Assay}} = 1;
  $DEBUG->{CATEGORIES}->{$track->{"Data Category"}} = 1;
  $DEBUG->{CLASSIFICATIONS}->{$track->{classification}} = 1;

  my $antibody = ($track->{Antibody} ne "Not applicable") ? $track->{Antibody} : undef;
  if ($antibody) {
    $antibody =~ s/-human//g;
  }
  
  my $trackName = (exists $track->{trackName}) ? $track->{trackName}
    : ($antibody) ? join(' ', [$track->{"Data Source"}, $track->{"original cell type name"}, $antibody, $track->{classification}])
    : join(' ', [$track->{"Data Source"}, $track->{"original cell type name"}, $track->{classification}]);
  #   "trackName": "FANTOM5_Enhancers Neuronal stem cell CAGE-Seq Enhancer peaks",
  $trackName =~ s/\s\[.*\]//g; # [original cell type; lab ]
  $trackName =~ s/\s\(bed\d*\)//g; # (bed12) / (narrowPeaks)
  $trackName =~ s/_/ /g;

  my $isGeneratedName = (exists $track->{trackName}) ? 0 : 1;

  my $trackKey = ($isGeneratedName) ? "generated//$trackName" : $track->{trackName};
  if (exists $DEBUG->{TRACK_NAMES}->{$trackName}) {
    my @trackIds = (exists $DEBUG->{TRACK_NAMES}->{$trackName}->{$trackKey})
      ? @{$DEBUG->{TRACK_NAMES}->{$trackName}->{$trackKey}}
      : ();
    push(@trackIds, $sourceId);
    $DEBUG->{TRACK_NAMES}->{$trackName}->{$trackKey} = \@trackIds;

  }
  else {
    $DEBUG->{TRACK_NAMES}->{$trackName}->{$trackKey} = ($sourceId);
  }

  
  $protocolAppNode->setName($trackName);
  my $description = (exists $track->{description}) ? $track->{description} : ($track->{trackName} ne $trackName)
    ? $track->{trackName} : undef;
  $protocolAppNode->setDescription($description) if ($description);

  my $updatedTrack = $self->patchCharacteristics($track);
  
  if (!$updatedTrack) {
    $self->log("INVALID ONTOLOGY TERMS; SKIPPING TRACK: $sourceId");
    $SKIP_COUNT++;
    return undef;
  }

  $updatedTrack->{genome_browser} = {track_name => $trackName};
  if ($description) {
    $updatedTrack->{genome_browser}->{track_description} = $description;
  }

  $updatedTrack = $self->cleanUpTrackJson($updatedTrack);
  if ($self->getArg('logCompletedTracks')) {
    my @tracks = @{$self->{completed_tracks}};

    if (!@tracks) {
      @tracks = Utils::to_json($updatedTrack, 1);
    }
    else {
      push(@tracks, Utils::to_json($updatedTrack, 1));
    }
    $self->{completed_tracks} = \@tracks;
  }
  
  $self->log("DEBUG: " . Dumper($updatedTrack)) if $self->getArg('veryVerbose');
  $protocolAppNode->setTrackSummary(Utils::to_json($updatedTrack));

  $protocolAppNode->submit();
  #$self->loadStudyLink($protocolAppNode->getProtocolAppNodeId())
  #  if ($self->getArg('study'));


  $self->undefPointerCache();
  return $protocolAppNode->getProtocolAppNodeId();
}


sub cleanUpTrackJson {
  my ($self, $track) = @_;

  # remove weird characters (e.g., #)
  # lower case w/no spaces

  for my $key ( keys %$track ) {
    (my $newKey = $key) =~ s/\s/_/g;
    $newKey =~ s/#//g;

    if ($newKey !~ /_/) {
      $newKey = decamelize($newKey)
    }
    else {
      $newKey = lc $newKey;
    }

    $newKey =~ s/encode/ENCODE/g;
    
    $track->{$newKey} = delete $track->{$key};
  }
  return $track;
}


sub patchCharacteristics {
  my ($self, $track) = @_;
  #   "Biosample type": "cell",
  #   "Biosamples term id": "CL:0000047",
  #   "Tissue category": "Stem Cell", -> Biosample Category

  my $filerSampleType = $track->{"Biosample type"};

  my $filerSampleId = $track->{"Biosamples term id"};
  my $filerSampleTerm = $track->{"cell type"};
  my $filerTermKey = join('//', $filerSampleId, $filerSampleTerm);

  my $filerTissueCategory = $track->{"Tissue category"};
  my $filerSystemCategory = $track->{"system category"};

  my $validatedSampleType = (exists $DEBUG->{TYPES}->{$filerSampleType}) 
    ? $DEBUG->{TYPES}->{$filerSampleType}
    : $self->validateBiosampleOntologyTerm($filerSampleType);

  my $validatedSample = (exists $DEBUG->{PARSED_BIOSAMPLES}->{$filerTermKey})
    ? $DEBUG->{PARSED_BIOSAMPLES}->{$filerTermKey}
    : ($filerSampleId)
    ? $self->validateBiosampleOntologyTerm($filerSampleId)
    : $self->validateBiosampleOntologyTerm($filerSampleTerm);

  my $validatedTissueCategory = (exists $DEBUG->{TISSUES}->{$filerTissueCategory})
    ? $DEBUG->{TISSUES}->{$filerTissueCategory}
    : $self->validateBiosampleOntologyTerm($filerTissueCategory);

  my $validatedSystemCategory = (exists $DEBUG->{SYSTEMS}->{$filerSystemCategory}) ?
    $DEBUG->{SYSTEMS}->{$filerSystemCategory} 
    : $self->validateBiosampleOntologyTerm($filerSystemCategory);

  # sample
  my $validatedTermKey = "invalid//$filerTermKey";
  if (!$validatedSample) {
    $self->log("INVALID Sample: ID - $filerSampleId / TERM - $filerSampleTerm")
      if ($self->getArg('veryVerbose'));
    $DEBUG->{INVALID_TERMS}->{BS}->{$filerSampleId} = {invalid_filer_annotation => 'cell type',
						       tissue_category => $filerTissueCategory,
						       system_category => $filerSystemCategory,
						       term => $filerSampleTerm,
						       term_id => $filerSampleId};
  }
  else {
    $validatedTermKey = join('//', $validatedSample->{term_id}, $validatedSample->{term});
    $self->isNSO("$filerSampleId//$filerSampleTerm", $validatedSample);
  }

  $DEBUG->{PARSED_BIOSAMPLES}->{$filerTermKey} = $validatedSample # this way it is undef if not validated
    if (!exists $DEBUG->{PARSED_BIOSAMPLES}->{$filerTermKey});


  # tissue category
  if(!$validatedTissueCategory) { # invalid?
    $DEBUG->{INVALID_TERMS}->{TISSUES}->{$filerTissueCategory} = {invalid_filer_annotation => 'tissue category',
							     tissue_category => $filerTissueCategory,
							     system_category => $filerSystemCategory,
							     term => $filerSampleTerm,
							     term_id => $filerSampleId};
    $self->log("INVALID  Tissue Category: $filerTissueCategory / TERM - $filerSampleTerm")
	if ($self->getArg('veryVerbose'));
  }

  else { # valid but possible NSO
    $validatedTissueCategory->{system_category} = ($validatedSystemCategory) 
      ? {term => $validatedSystemCategory->{term}, term_id => $validatedSystemCategory->{term_id}}
      : {term => "invalid//$filerSystemCategory"};
    $self->isNSO($filerTissueCategory, $validatedTissueCategory);
  }

  if (!exists $DEBUG->{TISSUES}->{$filerTissueCategory}) {
    $DEBUG->{TISSUES}->{$filerTissueCategory} = ($validatedTissueCategory) ? $validatedTissueCategory
      : {term => $filerTissueCategory};
  }

  # biosamples assigned to the tissue
  my @tBiosamples = (exists $DEBUG->{TISSUES}->{$filerTissueCategory}->{biosamples})
    ? @{$DEBUG->{TISSUES}->{$filerTissueCategory}->{biosamples}} : ();

  push(@tBiosamples, $validatedTermKey);
  @tBiosamples = uniq (@tBiosamples);

  $DEBUG->{TISSUES}->{$filerTissueCategory}->{biosamples} = \@tBiosamples;

  # system category
  if(!$validatedSystemCategory) {
    $self->log("INVALID System Category: $filerSystemCategory / TERM - $filerSampleTerm")
           if ($self->getArg('veryVerbose'));
    $DEBUG->{INVALID_TERMS}->{SC}->{$filerSystemCategory} = {invalid_filer_annotation => 'system category',
							     tissue_category => $filerTissueCategory,
							     system_category => $filerSystemCategory,
							     term => $filerSampleTerm,
							     term_id => $filerSampleId};
  }
  else {
    $self->isNSO($filerSystemCategory, $validatedSystemCategory);
  }
  if (!exists $DEBUG->{SYSTEMS}->{$filerSystemCategory}) {
    $DEBUG->{SYSTEMS}->{$filerSystemCategory} = ($validatedSystemCategory) ? $validatedSystemCategory
      : {term => $filerSystemCategory};
  }
  my @tTissues = (exists $DEBUG->{SYSTEMS}->{$filerSystemCategory}->{tissues})
    ? @{$DEBUG->{SYSTEMS}->{$filerSystemCategory}->{tissues}} : ();
  push(@tTissues, $filerTissueCategory);
  @tTissues = uniq(@tTissues);
  $DEBUG->{SYSTEMS}->{$filerSystemCategory}->{tissues} = \@tTissues;
  
  

  if ($validatedSample && $validatedTissueCategory && $validatedSystemCategory) {
    #if ($validatedSample->{definition} =~ m/dervive|differentiat/i) {
    #  $DEBUG->DERVIVED->{$validatedSample->{term}} = $validatedSample;
    #}
    
    my $isCellLine = ($validatedSampleType->{term} =~ m/cell line/) ? 1 : 0;

    my $cellLine = ($isCellLine)
      ? {
	 term => $validatedSample->{term},
	 term_id => $validatedSample->{term_id},
	 definition => $validatedSample->{definition}
	}
      : undef;

    $validatedSample = ($isCellLine)
      ? {
	 term => "cell type from cell line TBD",
	 term_id => "cell type from cell line TBD",
	 definition => "cell type from cell line TBD"
	}
      : $validatedSample;
    
    my $biosampleType = ($isCellLine) ? "cell" :  $validatedSampleType->{term};
    # = $self->getCellFromCellLine($validatedSample);
    
    my $isStemCell = ($validatedSample->{term} =~ m/stem cell/i) ? "true" : "TBD";
    my $isCancer = ($validatedSample->{definition} =~ m/cancer/i) ? "true" : "TBD";
    
    # TODO: cancer, differentiated flags, cell lines -> cells mapping
    my $biosample = {
		     biosample_type => $biosampleType,
		     defintion => $validatedSample->{definition},
		     term => $validatedSample->{term},
		     mapped_value => $validatedSample->{lookup},
		     term_id => $validatedSample->{term_id},
		     category => $validatedTissueCategory->{term},
		     system => $validatedSystemCategory->{term},
		     flags => { is_cancer => $isCancer,
				is_stem_cell => $isStemCell,
				is_differentiated => "TBD",
				cell_line => $cellLine}
		    };
    
    if ($validatedSample->{definition} =~ m/cancer/i) {
      $DEBUG->{CANCER}->{$validatedSample->{term}} = $biosample;
    }
    
    if ($isCellLine) {
      $DEBUG->{CELL_LINES}->{$filerTermKey} = $biosample;
    }

    $self->log(Dumper({$filerSampleTerm => $biosample}))
      if $self->getArg('verbose');
    $track->{biosample} = $biosample;
    return $track;
    # [{biosample_type: cell ,term: term_id: , cell_line: {term, term_id}}, {}]
  }

  # catch cell lines that are invalid
  if ($filerSampleType =~ m/cell line/) {
    $DEBUG->{CELL_LINES}->{$filerTermKey} = {term => "invalid//$filerTermKey"};
  }
  return undef;
}

sub isNSO { # flag non CL/CLO/UBERON terms
  my ($self, $filerTerm, $mappedTerm) = @_;

  if ($mappedTerm->{term_id} !~ m/CL_|CLO_|UBERON_/) {
    $DEBUG->{NS_ONTOLOGIES}->{$filerTerm} = $mappedTerm;
  }
}

sub validateBiosampleOntologyTerm {
  my ($self, $lookupValue) = @_;

  $lookupValue = $BIOSAMPLE_TERM_MAPPINGS->{$lookupValue}
    if (exists $BIOSAMPLE_TERM_MAPPINGS->{$lookupValue});

  $lookupValue = $BTO_TERM_MAPPINGS->{$lookupValue}
    if (exists $BTO_TERM_MAPPINGS->{$lookupValue});

  my $selectSql =<<SQL;
SELECT ontology_term_id, name, source_id, definition, 
CASE WHEN source_id LIKE 'UBERON%' THEN 1
WHEN source_id LIKE 'CL%' AND source_id NOT LIKE 'CLO%' THEN 2
WHEN source_id LIKE 'CLO%' THEN 3
ELSE 4 END AS ranking
SQL

  my $nameSql = "$selectSql FROM SRes.OntologyTerm WHERE lower(name) = lower(?) ORDER BY ranking LIMIT 1";
  my $termSql = "$selectSql FROM SRes.OntologyTerm WHERE source_id = replace(?, ':', '_') ORDER BY RANKING LIMIT 1";

  my @suffixes = ('', ' System', ' Tissue', ' Cell');
  my $found = 0;

  my ($ontologyTermId, $name, $sourceId, $definition, $ranking);
  
  foreach my $suffix (@suffixes) {
    my $qh = $self->getQueryHandle()->prepare($nameSql);
    $qh->execute($lookupValue . $suffix);
    ($ontologyTermId, $name, $sourceId, $definition, $ranking) = $qh->fetchrow_array();
    $qh->finish();
    return {term => $name, term_id=> $sourceId, definition => $definition, lookup => $lookupValue}
      if ($ontologyTermId);
  }
  
  if (!$ontologyTermId) {
    $qh = $self->getQueryHandle()->prepare($termSql);
    $qh->execute($lookupValue);
    ($ontologyTermId, $name, $sourceId, $definition, $ranking) = $qh->fetchrow_array();
    $qh->finish();
    return {term => $name, term_id=> $sourceId, definition => $definition, lookup => $lookupValue}
      if ($ontologyTermId);
  }
  
  $self->log("Term $lookupValue not found in SRes.OntologyTerm")
    if $self->getArg('veryVerbose');
  return undef;
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
