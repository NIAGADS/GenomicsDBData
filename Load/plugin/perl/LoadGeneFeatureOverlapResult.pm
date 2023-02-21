## LoadGeneFeatureOverlapResult Plugin
## $Id: LoadGeneFeatureOverlapResult.pm $

package GenomicsDBData::Load::Plugin::LoadGeneFeatureOverlapResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use GUS::PluginMgr::Plugin;
use Data::Dumper;
use JSON::XS;
use Scalar::Util qw(looks_like_number);
use POSIX        qw(strftime);

use Set::Scalar;
use List::MoreUtils   qw(uniq natatime);
use String::CamelCase qw(decamelize);

use URI;
use LWP::UserAgent;
use HTTP::Request;

use Package::Alias Utils       => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils => 'GenomicsDBData::Load::PluginUtils';

use GUS::Model::Results::GeneFeatureOverlap;
use GUS::Model::DoTS::Gene;

# data sources
my @ALLOWABLE_DATASOURCES =
  qw(DASHR2 DASHR2_small_RNA_Genes ENCODE ENCODE_roadmap FANTOM5_Enhancers FANTOM5 GTEx_v8 ROADMAP ROADMAP_Enhancers EpiMap);

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
    my $argumentDeclaration = [

        integerArg(
            {
                name           => 'requestSize',
                descr          => 'number of tracks to query simultaneously',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
                default        => 100
            }
        ),

        booleanArg(
            {
                name           => 'checkDuplicates',
                descr          => "check for duplicates",
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'filerUri',
                descr          => 'Uri for FILER data requests',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name           => 'genomeBuild',
                descr          => 'genome build (hg38 or hg19)',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name  => 'testGene',
                descr =>
'only load the specified gene; specify by official gene symbol or ensembl id; for testing',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name  => 'resumeAtGene',
                descr => 'resume load at gene, specified by ensembl_id',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name  => 'tracks',
                descr =>
'comma separated list of tracks to load; ignores allowable datasources',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
            }
        ),

        stringArg(
            {
                name  => 'extDbRlsSpec',
                descr =>
"The ExternalDBRelease specifier for FILER. Must be in the format 'name|version', where the name must match a name in SRes::ExternalDatabase and the version must match an associated version in SRes::ExternalDatabaseRelease.",
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),
    ];
    return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief =
      'Loads tallies of overlapping hits on a FILER track for a gene';

    my $purpose =
'This plugin queries the FILER API for gene regions and loads summary counts of hits per track.';

    my $tablesAffected = [
        [
            'Results::GeneFeatureOverlap',
            'Enters a row for each gene / track pair'
        ]
    ];

    my $tablesDependedOn = [DoTS::Gene];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2023. 
NOTES

    my $documentation = {
        purpose          => $purpose,
        purposeBrief     => $purposeBrief,
        tablesAffected   => $tablesAffected,
        tablesDependedOn => $tablesDependedOn,
        howToRestart     => $howToRestart,
        failureCases     => $failureCases,
        notes            => $notes
    };

    return $documentation;
}

# ----------------------------------------------------------------------
# create and initalize new plugin instance.
# ----------------------------------------------------------------------

sub new {
    my ($class) = @_;
    my $self = {};
    bless( $self, $class );

    my $documentation       = &getDocumentation();
    my $argumentDeclaration = &getArgumentsDeclaration();

    $self->initialize(
        {
            requiredDbVersion => 4.0,
            cvsRevision       => '6',
            name              => ref($self),
            revisionNotes     => '',
            argsDeclaration   => $argumentDeclaration,
            documentation     => $documentation
        }
    );
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

    $self->error("--testGene not yet implemented")
      if ( $self->getArg('testGene') );

    if ($self->getArg('tracks')) {
      my @tracks = split /,/, $self->getArg('tracks');
      my $nTracks = scalar @tracks;
      $self->log("INFO: User submitted N = $nTracks custom tracks");
    }

    $self->load();

    my @badTracks = @{$self->{bad_tracks}};
    $self->log("INFO: Bad Tracks found:" . (scalar @badTracks > 0) ? join(',', @badTracks) : "none"  )
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub load() {
    my ($self) = @_;
    my $extDbRlsId = $self->getExtDbRlsId( $self->getArg('extDbRlsSpec') );
    my @badTracks = ();
    $self->{bad_tracks} = \@badTracks;
    my $resumeAtGene =
      ( $self->getArg("resumeAtGene") )
      ? $self->fetchGeneId( $self->getArg("resumeAtGene") )
      : undef;

    my @genes       = @{ $self->queryGenes() };
    my $totalNGenes = scalar @genes;
    $self->log("Retrieved N = $totalNGenes genes.");
    my $nGenes = 0;

    foreach my $gene (@genes) {
        my $gid    = $gene->{SOURCE_ID};
        if ($resumeAtGene) {
          if ($gid ne $resumeAtGene ) {
            $self->log("WARNING: Resume point not met; SKIPPING $gid");
            next;
          }
          $self->log("INFO: Found resumeAtGene = $gid; resuming load");
          $resumeAtGene = undef;
        }
        my $symbol = $gene->{GENE_SYMBOL};
        my $span =
            $gene->{CHROMOSOME} . ':'
          . $gene->{LOCATION_START} . '-'
          . $gene->{LOCATION_END};
        $self->log("INFO: Querying Gene: $gid - $symbol : $span");

        my $dotsGeneId = $gene->{GENE_ID};
        my $chromosome = $gene->{CHROMOSOME};

        my @dataSources = ($self->getArg('tracks')) ? qw(custom_track_list) : @ALLOWABLE_DATASOURCES;


        foreach my $ds (@dataSources) {

            my @overlappingTracks = ($ds ne "custom_track_list") 
              ? $self->fetchOverlappingFILERTracks( $span, $ds ) 
              : $self->findValidTracks($span, $self->getArg('tracks'));
              # :  split /,/, $self->getArg('tracks');


            my $nOverlappingTracks = scalar @overlappingTracks;
            next if ($nOverlappingTracks == 1 && $overlappingTracks[0] eq "error");
            $self->log("INFO: Found N = $nOverlappingTracks overlapping tracks for $gid in $ds");
            
            # slice to avoid long urls (eg., ENCODE -- too many tracks)
            # split into groups of 25 tracks
            my $trackIter = natatime $self->getArg('requestSize'), @overlappingTracks;
            my $trackCount = 0;
            my $resultSize = 0;
            while ( my @trackSubset = $trackIter->() ) {
                $trackCount += scalar @trackSubset;
                my $result = $self->fetchFILERHits( $span, \@trackSubset );
                foreach my $track (@$result) {
                    my $trackId  = $track->{Identifier};
                    my @features = @{ $track->{features} };
                    $resultSize += scalar @features;

                    foreach my $hit (@features) {
                        my $geneFeatureOverlap =
                          GUS::Model::Results::GeneFeatureOverlap->new(
                            {
                                gene_id                      => $dotsGeneId,
                                external_database_release_id => $extDbRlsId,
                                filer_track_id               => $trackId,
                                chromosome                   => $chromosome,
                                location_start => $hit->{chromStart},
                                location_end   => $hit->{chromEnd},
                                hit_stats      => Utils::to_json($hit)
                            }
                          );

                        if ( $self->getArg('checkDuplicates') ) {
                            $geneFeatureOverlap->submit()
                              unless $geneFeatureOverlap->retrieveFromDB();
                        }
                        else {
                            $geneFeatureOverlap->submit();
                        }
                    }
                }
                $self->log("INFO: Found N = $resultSize hits for $gid in $ds (Processed $trackCount / $nOverlappingTracks)") 
                  if $self->getArg('verbose');
            }
            $self->log("INFO: Found N = $resultSize hits for $gid in $ds (Processed $trackCount / $nOverlappingTracks)")
              if !$self->getArg('verbose');
        }

        $self->undefPointerCache();

        if ( ++$nGenes % 1000 == 0 ) {
            $self->log("Processed $nGenes / $totalNGenes");
        }
    }

}

# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------

sub findValidTracks {
  my ($self, $span, $trackStr) = @_;

  my $userTracks = Set::Scalar->new(split /,/, $trackStr);

  my @overlappingTracks = $self->fetchOverlappingFILERTracks( $span, undef );
  return qw(error) if (!@overlappingTracks);

  my $oTracks = Set::Scalar->new(@overlappingTracks);

  my $validTracks = $oTracks->intersection($userTracks);
  return @$validTracks;
}

sub removeBadTracks {
  my ($self, $tracks) = @_;
  my @badTracks = @{$self->{bad_tracks}};
  my @revisedTracks = @$tracks;
  my $nBadTracks = scalar @badTracks;
  if ($nBadTracks > 0) {
      foreach my $bt (@badTracks) {
        @revisedTracks =  grep {$_ ne $bt} @revisedTracks;
      }

      $self->log("INFO: Removed $nBadTracks bad tracks");
      return @revisedTracks;
  }
  else {
    return @$tracks;
  }
}

sub queryGenes {
    my ($self) = @_;

    my @result = ();
    my $sql = "SELECT source_id, gene_id, gene_symbol, chromosome, location_start, location_end FROM CBIL.GeneAttributes ORDER BY gene_id";
    my $qh = $self->getQueryHandle()->prepare($sql) || $self->error(DBI::errstr);
    $qh->execute();
    while ( my $gene = $qh->fetchrow_hashref() ) {
        push( @result, $gene );
    }
    $qh->finish();
    return \@result;
}

sub fetchGeneId {
  my ($self, $gid)  = @_;
  my $sql = "SELECT source_id FROM CBIL.GeneAttributes WHERE source_id = ? OR gene_symbol = ?";
  my $qh = $self->getQueryHandle()->prepare($sql) || $self->error(DBI::errstr);
  $qh->execute($gid, $gid);
  my ($sourceId) = $qh->fetchrow_array();
  $qh->finish();
  return $sourceId;
}

# https://tf.lisanwanglab.org/FILER/get_overlaps.php?trackIDs=NGEN000611,NGEN000615,NGEN000650&region=chr1:50000-1500000
sub fetchFILERHits {
    my ( $self, $span, $tracks ) = @_;

    my $requestUrl = $self->getArg('filerUri') . "/get_overlaps.php";
    my %params     = (
        trackIDs => join( ',', @$tracks ),
        region   => $span,
    );

    $self->log( "FETCHING FILER hits from $requestUrl with parameters: "
          . Dumper( \%params ) )
      if $self->getArg('veryVerbose');
    my $ua = LWP::UserAgent->new();
    $ua->ssl_opts( verify_hostname => 0 );    # filer certificate is often bad
    my $uri = URI->new($requestUrl);
    $uri->query_form(%params);
    my $response = $ua->get($uri);
 
    if ( $response->is_success() ) {
        if ($response->content =~ /ERROR: requested track (.+) not found/) {
          my $badTrack = $1;
          $self->log("Bad track $badTrack; removing from list and resubmitting");
          my @bts = $self->{bad_tracks};
          push(@bts, $badTrack);
          $self->{bad_tracks} = \@bts;
          my @revisedTracks = grep {$_ ne $badTrack} @$tracks;
          return $self->fetchFILERHits($span, \@revisedTracks);
        }
        # $self->log("DEBUG:" . $response->content);
        my $json = JSON::XS->new;
        my $hits = $json->decode( $response->content )
          || $self->error("Error fetching overlapping track JSON: $!");
        return $hits;
    }

    else {
        $self->error(
            "FETCH ERROR: GET $uri failed: " . $response->status_line );
    }

}

# https://tf.lisanwanglab.org/FILER/get_overlapping_tracks_by_coord.php?genomeBuild=hg38&region=chr1:1103243-1103243&filterString=.&outputFormat=json
sub fetchOverlappingFILERTracks {
    my ( $self, $span, $dataSource ) = @_;

    my $requestUrl =
      $self->getArg('filerUri') . "/get_overlapping_tracks_by_coord.php";
    my %params =  (
        genomeBuild  => $self->getArg('genomeBuild'),
        filterString => ($dataSource) ? '."Data Source"=="' . $dataSource . '"' : '.',
        region       => $span,
        outputFormat => "json"
    );


    $self->log(
        "FETCHING list of overlapping tracks from $requestUrl with parameters: "
          . Dumper( \%params ) )
      if $self->getArg('veryVerbose');
    my $ua = LWP::UserAgent->new();
    $ua->ssl_opts( verify_hostname => 0 );    # filer certificate is often bad
    my $uri = URI->new($requestUrl);
    $uri->query_form(%params);
    my $response = $ua->get($uri);

    if ( $response->is_success() ) {
        my $json              = JSON::XS->new;
        my $overlappingTracks = $json->decode( $response->content )
          || $self->error("Error fetching overlapping track JSON: $!");

        push @trackIds, $_->{Identifier} for @$overlappingTracks;
        return @trackIds;
    }

    else {
        $self->log(
            "ERROR: GET $uri failed: " . $response->status_line . " - SKIPPING $span" );
            return undef;
    }

}

# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;
    my @tables = qw(Results.GeneFeatureOverlap);
    return @tables;
}

1;
