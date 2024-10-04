## $Id: LoadVariantGWASResult.pm $
##
package GenomicsDBData::GWAS::Plugin::LoadVariantGWASResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;
use GUS::Model::Results::VariantGWAS;
use GUS::Model::Study::ProtocolAppNode;

BEGIN { $Package::Alias::BRAVE = 1 }
use Package::Alias Utils            => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils      => 'GenomicsDBData::Load::PluginUtils';

use JSON::XS;
use Data::Dumper;
use File::Spec;

my $RESTRICTED_STATS_FIELD_MAP = undef;

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my @INPUT_FIELDS =
  qw(chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json);
my @RESULT_FIELDS =
  qw(chr bp allele1 allele2 freq1 pvalue neg_log10_p display_p gwas_flags test_allele restricted_stats_json db_variant_json);
my @RESTRICTED_STATS_ORDER =
  qw(num_observations coded_allele_frequency minor_allele_count call_rate test min_frequency max_frequency frequency_se effect beta t_statistic std_err odds_ratio beta_std_err beta_L95 beta_U95 odds_ratio_L95 odds_ratio_U95 hazard_ratio hazard_ratio_CI95 direction het_chi_sq het_i_sq het_df het_pvalue probe maf_case maf_control p_additive p_dominant p_recessive Z_additive Z_dominant Z_recessive);
my @VCF_FIELDS = qw(#CHROM POS ID REF ALT QUAL FILTER INFO);

my $COPY_SQL = <<COPYSQL;
COPY Results.VariantGWAS(
protocol_app_node_id,
variant_record_primary_key,
bin_index,
neg_log10_pvalue,
pvalue_display,
frequency,
allele,
restricted_stats,
chromosome,
position,
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
    my $argumentDeclaration = [  
        fileArg(
            {
                name           => 'file',
                descr          => 'full path to input file',
                constraintFunc => undef,
                reqd           => 1,
                mustExist      => 1,
                isList         => 0,
                format         => 'tab delim text'
            }
        ),

        stringArg(
            {
                name           => 'sourceId',
                descr          => 'protocol app node source id',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'frequency',
                descr          => '(optional) column containing freqency value',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'marker',
                descr          => '(optional) column containing marker name',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'testAllele',
                descr          => 'column containg test allele',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'refAllele',
                descr          => 'column containg ref allele',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'altAllele',
                descr => '(optional) only specify if input has 3 allele columns (e.g., major, minor, test)',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'chromosome',
                descr          => 'column containg chromosome',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'gwsThreshold',
                descr => 'threshold for flagging result has having genome wide signficiance; provide in scientific notation',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
                default        => '5e-8'
            }
        ),

        stringArg(
            {
                name           => 'position',
                descr          => 'column containing position',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name           => 'pvalue',
                descr          => 'column containing pvalue',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'restrictedStats',
                descr => 'json object of key value pairs for additional scores/annotations that have restricted access',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        stringArg(
            {
                name  => 'customChrMap',
                descr => 'json object defining custom mappings (e.g., {"25":"M", "Z": "5"}',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0
            }
        ),

        booleanArg(
            {
                name  => 'preprocess',
                descr =>
                  'generate input file that can be passed to DB lookup scripts',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        booleanArg(
            {
                name  => 'skipUndoSummary',
                descr =>
                  'do not calculate table entries for UNDO; can take a while',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
            }
        ),

        integerArg(
            {
                name  => 'commitAfter',
                descr => 'files matching the listed pattern (e.g., chrN)',
                constraintFunc => undef,
                isList         => 0,
                default        => 100000,
                reqd           => 0
            }
        ),
    
    ];
    return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
    my $purposeBrief = 'Loads Variant GWAS result';

    my $purpose =
'Loads Variant GWAS result in multiple passes: 1) generate input file that can be passed on to DB mapping scripts; 2) load a result';

    my $tablesAffected =
      [ [ 'Results::VariantGWAS', 'Enters a row for each variant feature' ]];

    my $tablesDependedOn =
      [ [ 'Study::ProtocolAppNode', 'lookup analysis source_id' ] ];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;

Written by Emily Greenfest-Allen
modified from GenomicsDBData/Load/plugin/perl/deprecated/LoadVariantGWASResult
Copyright Trustees of University of Pennsylvania 2024. 
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
            cvsRevision       => '$Revision: 3$',
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

    my $preprocess = $self->initializePlugin();
    $self->preprocess() if ($preprocess);
    $self->loadResult() if (!$preprocess);
}


# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub initializePlugin {
    my ($self) = @_;

    $self->logAlgInvocationId();
    $self->logCommit();
    $self->logArgs();
    $self->getAlgInvocation()->setMaximumNumberOfObjects(100000);

    $self->{housekeeping} = PluginUtils::buildHouseKeepingString($self);

    return $self->processArgs();
}


sub preprocess {
    my ( $self ) = @_;

    my $file = $self->getArg("file");
    $self->log("INFO: Cleaning $file");

    my ($v, $workingDir, $f) = File::Spec->splitpath($file);
    $workingDir = PluginUtils::createDirectory($self,  $workingDir, 'preprocess');
    
    my $inputFileName = File::Spec->catfile($workingDir, $self->getArg('sourceId') . "-input.txt");
    $self->log("INFO: Writing cleaned input to: $inputFileName");
    
    my $pfh = undef;
    open( $pfh, '>', $inputFileName ) || $self->error("Unable to create cleaned file $inputFileName for writing");
    print $pfh join( "\t", @INPUT_FIELDS ) . "\n";
    $pfh->autoflush(1);

    open( my $fh, $file ) || $self->error("Unable to open original file $file for reading");

    my $header = <$fh>;
    chomp($header);
    my @fields = split /\t/, $header;
    @fields = split /\s/, $header if ( scalar @fields == 1 );
    @fields = split /,/,  $header if ( scalar @fields == 1 );

    my %columns = map { $fields[$_] => $_ } 0 .. $#fields;
    if ( $self->getArg('restrictedStats') ) {
        $self->generateRestrictedStatsFieldMapping( \%columns )
          if ( !$RESTRICTED_STATS_FIELD_MAP );
    }

    # arg validation done in `processArgs`
    my $testAlleleC = $self->getColumnIndex(\%columns, $self->getArg('testAllele'));
    my $refAlleleC = $self->getColumnIndex(\%columns, $self->getArg('refAllele'));
    my $chrC = $self->getColumnIndex(\%columns, $self->getArg('chromosome'));
    my $positionC = $self->getColumnIndex(\%columns, $self->getArg('position'));
    
    # optional
    my $altAlleleC = ($self->getArg('altAllele'))
      ? $self->getColumnIndex( \%columns, $self->getArg('altAllele'))
      : undef;

    my $frequencyC =  ($self->getArg('frequency'))
        ? $self->getColumnIndex(\%columns, $self->getArg('frequency'))
        : undef;

    my $markerC = ($self->getArg('marker'))
      ? $self->getColumnIndex( \%columns, $self->getArg('marker'))
      : undef;

    # process the file
    my $lineCount = 0;
    my $skipCount = 0;

    while (my $line = <$fh>) {
        chomp $line;

        my @values = split /\t/, $line;
        @values = split /\s/, $line if (scalar @values == 1);
        @values = split /,/,  $line if (scalar @values == 1);

        my $skip = 0;

        my $chromosome = $values[$chrC];
        if ($chromosome eq "0" || $chromosome eq "NULL" || !defined $chromosome) {
            $self->log("WARNING: chromosome undefined; skipping: $line")
                if $self->getArg('verbose');
            $skipCount++;
            $skip = 1;
        }
        $chromosome = $self->correctChromosome($chromosome);

        my $position   = $values[$positionC];
        if ($position == 0)  {
            $self->log("WARNING: position = 0; skipping line: $line")
                if ($self->getArg('verbose'));
            $skipCount++;
            $skip = 1;
        }


        my $frequency = (defined $frequencyC) ? $values[$frequencyC] : undef;
        my $marker = (defined $markerC) ? $values[$markerC] : undef;
        $marker = 'NULL' if $marker eq 'NA' or $marker eq '.';

        my $ref = uc($values[$refAlleleC]);
        my $alt = ($altAlleleC) ? uc($values[$altAlleleC]) : uc( $values[$testAlleleC]);
        my $test = uc($values[$testAlleleC]);

        my $metaseqId  = "$chromosome:$position:$ref:$alt";

        my $rv = {
            chromosome => $chromosome,
            position   => $position,
            refAllele  => $ref,
            altAllele  => $alt,
            testAllele => $test,
            marker     => $marker,
            metaseq_id => $metaseqId
        };

        $self->writeCleanedInput($pfh, $rv, \%columns, @values ) 
            if (!$skip);

        if ( ++$lineCount % 500000 == 0 ) {
            $self->log("INFO: Cleaned $lineCount lines");
        }
    }

    $self->log("INFO: Cleaned $lineCount lines");
    $self->log("INFO: Skipped $skipCount lines due to missing positional information.");
    return $inputFileName;
}    # end preprocess


sub loadResult {
    my ($self) = @_;
    $self->log("INFO: Loading GWAS summary statistics into Results.VariantGWAS");

    my ($v, $workingDir, $f) = File::Spec->splitpath($self->getArg('file'));
    my $inputFileName = File::Spec->catfile($workingDir, 'preprocess', $self->getArg('sourceId') . "-input.txt.map");
    $self->log("INFO: Loading from file: $inputFileName");

    open(my $fh, $inputFileName) || $self->error("Unable to open $inputFileName for reading");

    my $header          = <$fh>;
    my $recordCount     = 0;
    my $nullSkipCount = 0;

    my $commitAfter     = $self->getArg('commitAfter');
    my $msgPrefix     = ($self->getArg('commit')) ? 'COMMITTED' : 'PROCESSED';

    my $insertStrBuffer = "";
    my %row;
    my $json            = JSON::XS->new();

    push(@INPUT_FIELDS, ("db_mapped_variant"));

    while (my $line = <$fh>) {
        chomp($line);
        @row{@INPUT_FIELDS} = split /\t/, $line;

        # don't load NULL (missing) pvalues as they are useless for project
        if ($row{pvalue} eq 'NULL') {  
            $nullSkipCount++;
            next;
       }

        $self->error("Unmapped variant found: " . $row{metaseq_id}) 
            if $row{db_mapped_variant} eq 'NULL';
       
        my $mappedVariants  = $json->decode($row{db_mapped_variant});
        foreach my $mv (@$mappedVariants) {
            $insertStrBuffer .= $self->generateInsertStr($mv->{primary_key},
                $mv->{bin_index}, \%row);
            if (++$recordCount % $commitAfter == 0) {
                PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
                $insertStrBuffer = "";
                $self->log("$msgPrefix: $recordCount Results");
           }
       }
   }

    # residuals
    if ($insertStrBuffer ne "") {
        PluginUtils::bulkCopy($self, $insertStrBuffer, $COPY_SQL);
        $self->log("$msgPrefix: $recordCount Results");
   }

    $self->log("DONE - $msgPrefix: $recordCount Results");
    $self->log("WARNING - SKIPPED: $nullSkipCount Results with NULL p-value");
}

# ----------------------------------------------------------------------
# helper methods
# ----------------------------------------------------------------------

sub processArgs {
    my ($self) = @_;

    my $preprocess = $self->getArg('preprocess');

    if ($preprocess) {
        $self->{custom_chr_map} =
        ( $self->getArg('customChrMap') )
        ? $self->generateCustomChrMap()
        : undef;

        $self->error("must specify chromomosome")
            if (!$self->getArg('chromosome'));
        $self->error("must specify position")
            if (!$self->getArg('position'));
        $self->error("must specify testAllele")
          if ( !$self->getArg('testAllele'));
        $self->error("must specify refAllele")
          if ( !$self->getArg('refAllele') && !$self->getArg('marker'));
        $self->error("must specify pvalue") if (!$self->getArg('pvalue'));
    }

    else {
        $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();   
    }

    return $preprocess
}

sub getProtocolAppNodeId {
    my ($self) = @_;

    my $protocolAppNode = GUS::Model::Study::ProtocolAppNode->new(
        { source_id => $self->getArg('sourceId') } );

    $self->error(
        "No protocol app node found for " . $self->getArg('sourceId') )
      unless $protocolAppNode->retrieveFromDB();

    return $protocolAppNode->getProtocolAppNodeId();
}

sub generateCustomChrMap {
    my ($self) = @_;
    my $json   = JSON::XS->new;
    my $chrMap = $json->decode( $self->getArg('customChrMap') )
      || $self->error("Error parsing custom chromosome map");
    $self->log( "Found custom chromosome mapping: " . Dumper( \$chrMap ) );
    return $chrMap;
}

sub generateInsertStr {
    my ( $self, $recordPK, $binIndex, $data ) = @_;
    my @values = (
        $self->{protocol_app_node_id}, $recordPK,
        $binIndex,                     $data->{neg_log10_p},
        $data->{display_p},            $data->{freq1},
        $data->{test_allele},          $data->{restricted_stats_json},
        'chr' . $data->{chr},          $data->{bp}
    );
    push( @values, GenomicsDBData::Load::Utils::getCurrentTime() );
    push( @values, $self->{housekeeping} );
    my $str = join( "|", @values );
    return "$str\n";
}

sub getColumnIndex {
    my ( $self, $columnMap, $field ) = @_;

    $self->error("$field not in file header")
      if ( !exists $columnMap->{$field} );

    return $columnMap->{$field};
}

# ----------------------------------------------------------------------
# file manipulation methods
# ----------------------------------------------------------------------

sub writeCleanedInput {
    my ( $self, $fh, $resultVariant, $fields, @values ) = @_;

    my $frequencyC =
      ( $self->getArg('frequency') )
      ? $fields->{ $self->getArg('frequency') }
      : undef;
    my $frequency = ( defined $frequencyC ) ? $values[$frequencyC] : 'NULL';
    my $pvalueC   = $fields->{ $self->getArg('pvalue') };
    my ( $pvalue, $negLog10p, $displayP ) =
      $self->formatPvalue( $values[$pvalueC] );

    my $restrictedStats = 'NULL';
    if ( $self->getArg('restrictedStats') ) {
        $restrictedStats = $self->buildRestrictedStatsJson(@values);
    }

    my $gwasFlags =
      ( $pvalue <= 0.001 )
      ? $self->buildGWASFlags( $pvalue, $displayP )
      : undef;

# (chr bp allele1 allele2 marker metaseq_id freq1 pvalue neg_log10_p display_p gws_flags test_allele restricted_stats_json)
    print $fh join(
        "\t",
        (
            $resultVariant->{chromosome} ? $resultVariant->{chromosome}
            : "NULL",
            $resultVariant->{position} ? $resultVariant->{position} : "NULL",
            $resultVariant->{altAllele},
            $resultVariant->{refAllele},
            ( $resultVariant->{marker} ) ? $resultVariant->{marker}
            : "NULL",
            (
                $resultVariant->{metaseq_id} =~ m/NA/g
                  || !$resultVariant->{metaseq_id}
              ) ? "NULL"
            : $resultVariant->{metaseq_id},
            $frequency,
            $pvalue,
            $negLog10p,
            $displayP,
            $gwasFlags ? $gwasFlags : "NULL",
            $resultVariant->{testAllele},
            $restrictedStats
        )
    ) . "\n";
}

# ----------------------------------------------------------------------
# attribute formatting
# ----------------------------------------------------------------------

sub cleanAllele {
    my ( $self, $allele ) = @_;

    $allele =~ s/<|>//g;
    $allele =~ s/:/\//g;
    return $allele;
}

sub correctChromosome {
    my ( $self, $chrm ) = @_;
    my $customChrMap = $self->{custom_chr_map};

    return ($chrm) if ( !$customChrMap );

    while ( my ( $oc, $rc ) = each %$customChrMap ) {
        $chrm = $rc if ( $chrm =~ m/\Q$oc/ );
    }

    $chrm = 'M' if ( $chrm =~ m/25/ );
    $chrm = 'M' if ( $chrm =~ m/MT/ );
    $chrm = 'X' if ( $chrm =~ m/23/ );
    $chrm = 'Y' if ( $chrm =~ m/24/ );
    return $chrm;
}

sub formatPvalue {
    my ( $self, $pvalue ) = @_;
    my $negLog10p = 0;

    return ( "NaN", "NaN", "NaN" )     if ( $pvalue =~ m/NAN/i );
    return ( "NULL", "NULL", "NULL" )  if ( $pvalue =~ m/NA$/ );
    return ( $pvalue, "NaN", $pvalue ) if ( $pvalue == 0 );
    return ( "NULL", "NULL", "NULL" )  if ( !$pvalue );

    if ( $pvalue =~ m/e/i ) {
        my ( $mantissa, $exponent ) = split /-/, $pvalue;
        return ( $pvalue, $exponent, $pvalue ) if ( $exponent > 300 );
    }

    return ( 1, 0, $pvalue ) if ( $pvalue == 1 );

    eval { $negLog10p = -1.0 * ( log($pvalue) / log(10) ); } or do {
        $self->log("WARNING: Cannot take log of p-value ($pvalue)");
        return ( $pvalue, $pvalue, $pvalue );
    };

    my $displayP = ( $pvalue < 0.0001 ) ? sprintf( "%.2e", $pvalue ) : $pvalue;

    return ( $pvalue, $negLog10p, $displayP );
}

sub generateRestrictedStatsFieldMapping {
    my ( $self, $columns ) = @_;
    my $json  = JSON::XS->new;
    my $stats = $json->decode( $self->getArg('restrictedStats') )
      || $self->error("Error parsing restricted stats JSON");

    $RESTRICTED_STATS_FIELD_MAP = {};
    while ( my ( $stat, $field ) = each %$stats ) {
        if ( $stat eq "other" ) {
            foreach my $fd (@$field) {
                $RESTRICTED_STATS_FIELD_MAP->{$fd} =
                  $self->getColumnIndex( $columns, $fd );
            }
        }
        else {
            $RESTRICTED_STATS_FIELD_MAP->{$stat} =
              $self->getColumnIndex( $columns, $field );
        }
    }
}

sub buildRestrictedStatsJson {
    my ( $self, @values ) = @_;
    my $stats = {};
    while ( my ( $stat, $index ) = each %$RESTRICTED_STATS_FIELD_MAP ) {
        my $tValue = lc( $values[$index] );
        if ( $tValue eq "infinity" or $tValue =~ m/^inf$/ ) {
            $stats->{$stat} = "Infinity";
        }
        else
        { # otherwise replaces Infinity w/inf which will cause problems w/load b/c inf s not a number in postgres
            $stats->{$stat} = Utils::toNumber( $values[$index] );
        }
    }
    return Utils::to_json($stats);
}

sub buildGWASFlags {
    my ( $self, $pvalue, $displayP ) = @_;
    my $flags = {
        $self->getArg('sourceId') => {
            p_value => Utils::toNumber($displayP),
            is_gws  => $pvalue <=
              $self->getArg('gwsThreshold') ? 1 : 0
        }
    };

    return Utils::to_json($flags);
}

# ----------------------------------------------------------------------
# clean and sort
# ----------------------------------------------------------------------

 
# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;
    if (!$self->getArg('skipUndoSummary') && !$self->getArg('preprocess')) {
        return ('Results.VariantGWAS') 
    }
    return ();
}
1;
