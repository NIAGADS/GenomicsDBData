## $Id: LoadQTLResult.pm $
##
package GenomicsDBData::GWAS::Plugin::LoadQTLGeneResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;
use GUS::Model::Results::QTLGene;
use GUS::Model::Study::ProtocolAppNode;

BEGIN { $Package::Alias::BRAVE = 1 }
use Package::Alias Utils            => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils      => 'GenomicsDBData::Load::PluginUtils';

use JSON::XS;
use Data::Dumper;
use File::Spec;

my $SHARD_PATTERN = "_chr(\d{1,2}|[XYM]|MT)_";

my $HOUSEKEEPING_FIELDS = PluginUtils::getHouseKeepingSql();

my %OTHER_STATS_FIELD_MAP = (
    target_strand => 5,
    target => 10, 
    z_score_non_ref => 11,
    beta_non_ref => 12,
    beta_se_non_ref => 13,
    FDR => 14,
    non_ref_af => 15,
    target_info => 18
);

my @EXPECTED_FIELDS = 
qw(#chrom chromStart chromEnd variant_id pval target_strand ref alt target_gene_symbol target_ensembl_id target z_score_non_ref beta_non_ref beta_se_non_ref FDR non_ref_af qtl_dist_to_target QC_info target_info user_input);

my @INPUT_FIELDS =
  qw(chr bp ref alt marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json);


my $COPY_SQL = <<COPYSQL;
COPY Results.QTLGene(
track_id,
variant_record_primary_key,
bin_index,
chromosome,
position,
test_allele,
neg_log10_pvalue,
pvalue_display,
target_ensembl_id,
dist_to_target,
other_stats,
num_qtls_targeting_gene,
rank,

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
        stringArg(
            {
                name           => 'fileDir',
                descr          => 'full path to input file directory',
                constraintFunc => undef,
                reqd           => 1,
                isList         => 0,

            }
        ),

        stringArg(
            {
                name           => 'pattern',
                descr          => 'file pattern to match for original input files; required for preprocessing',
                constraintFunc => undef,
                reqd           => 0,
                isList         => 0,
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

        

        booleanArg(
            {
                name  => 'skipUnmappedVariants',
                descr =>
                  'skip unmapped variants',
                constraintFunc => undef,
                isList         => 0,
                reqd           => 0
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
    my $purposeBrief = 'Loads QTL result';

    my $purpose =
'Loads Top QTL per gene result in multiple passes: 1) generate input file that can be passed on to DB mapping scripts; 2) load a result';

    my $tablesAffected =
      [ [ 'Results::QTLGene', 'Enters a row for each gene' ]];

    my $tablesDependedOn =
      [];

    my $howToRestart = '';

    my $failureCases = '';

    my $notes = <<NOTES;

Written by Emily Greenfest-Allen
Copyright Trustees of University of Pennsylvania 2025. 
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
            cvsRevision       => '$Revision: 8$',
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

    my $fileDir = $self->getArg("fileDir");
    my $pattern = $self->getArg('pattern');
    $self->log("INFO: Processing files in $fileDir that match $pattern");

    my $filePattern = File::Spec->catfile($fileDir, $pattern);
    my @files = glob($filePattern);
    $self->log("INFO: Found " . scalar @files . " files matching $pattern.");

    my $workingDir = PluginUtils::createDirectory($self,  $fileDir, 'preprocess');
    my $geneSummary = {};
    my $cleanedFileName;
    foreach my $fName (@files) {
        $cleanedFileName = $self->cleanFile($fName, $workingDir);
        $geneSummary = $self->updateGeneSummary($cleanedFileName, $workingDir, $geneSummary);
    }

    my $cmd = `rm $cleanedFileName`;  # remove the temporary file

    my $inputFileName = File::Spec->catfile($workingDir, $self->getArg('sourceId') . "-input.txt");
    open( my $fh, '>', $inputFileName ) || $self->error("Unable to create final input file $inputFileName for writing");
    $fh->autoflush(1);
       
    my @header = @INPUT_FIELDS;
    push(@header, 'num_qtls_targeting_gene');
    print $fh join( "\t", @header ) . "\n";

    while (my ($gene, $summary) = each %$geneSummary) {
        my $values = $summary->{hit};
        push(@$values, $summary->{hitCount});
        print $fh join("\t", @$values) . "\n";
    }

    $fh->close();

    my $geneCount = scalar keys %$geneSummary;
    $self->log("INFO: Found $geneCount genes.");
    $self->log("INFO: Gene summary written to $inputFileName");
}    # end preprocess

sub loadResult {
    my ($self) = @_;
    $self->log("INFO: Loading GWAS summary statistics into Results.QTL");

    my ($v, $workingDir, $f) = File::Spec->splitpath($self->getArg('file'));
    my $inputFileName = File::Spec->catfile($workingDir, 'preprocess', $self->getArg('sourceId') . "-input.txt.map");
    $self->log("INFO: Loading from file: $inputFileName");

    $self->log("INFO: sorting by -log10p");
    my $sortedFileName = $inputFileName . ".sorted";
    my $cmd = `(head -n 1 $inputFileName && tail -n +2 $inputFileName | sort -T $workingDir -V -r -k8 ) > $sortedFileName`;
    $self->log("Created sorted  file: $sortedFileName");

    $self->log("INFO: Loading from file: $sortedFileName");

    open(my $fh, $sortedFileName) || $self->error("Unable to open $sortedFileName for reading");

    my $header          = <$fh>;
    my $recordCount     = 0;
    my $nullSkipCount = 0;
    my $unmappedSkipCount = 0;

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
        if ($row{pvalue} eq 'NULL' || $row{pvalue} eq '0') {  
            $nullSkipCount++;
            next;
       }

        if($row{db_mapped_variant} eq 'NULL') {
            if ($self->getArg('skipUnmappedVariants')) {
                $unmappedSkipCount++;
                next;
            }
            else {
                $self->error("Unmapped variant found: " . $row{metaseq_id});
            }
        }
       
        my $mappedVariants  = $json->decode($row{db_mapped_variant});
        foreach my $mv (@$mappedVariants) {
            $insertStrBuffer .= $self->generateInsertStr(++$recordCount, 
                $mv->{primary_key},
                $mv->{bin_index}, \%row);
            if ($recordCount % $commitAfter == 0) {
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
    $self->log("WARNING - SKIPPED: $unmappedSkipCount Results not mapped to the database.");
}

# ----------------------------------------------------------------------
# helper methods
# ----------------------------------------------------------------------

sub processArgs {
    my ($self) = @_;

    my $preprocess = $self->getArg('preprocess');

    return $preprocess
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
    my ( $self, $rank, $recordPK, $binIndex, $data ) = @_;
    # $self->log("DEBUG: " . Dumper($data));

    my @values = (
        $self->getArg('sourceId'), $recordPK,
        $binIndex, 'chr' . $data->{chr},
        $data->{bp}, $data->{alt}, $data->{neg_log10_p},
        $data->{display_p}, $data->{target_ensembl_id},
        $data->{dist_to_target}, $data->{other_stats_json},
        $data->{num_qtls_in_gene},
        $rank     
    );
    push( @values, GenomicsDBData::Load::Utils::getCurrentTime() );
    push( @values, $self->{housekeeping} );
    my $str = join( "|", @values );
    # $self->log("DEBUG: $str");
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

sub updateGeneSummary {
    my ($self, $file, $workingDir, $geneSummary) = @_;

    $self->log("INFO: Updating Gene Summary");

    my $json = JSON::XS->new();
    my %row;

    # qw(chr bp ref alt marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json);
    open( my $fh, $file ) || $self->error("Unable to open file $file for reading");
    my $h = <$fh>; # skip header

    while (my $line = <$fh>) {
        chomp $line;  
        @row{@INPUT_FIELDS} = split /\t/, $line; 

        # qw(chr bp ref alt marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json);
        my $targetGene = $row{target_ensembl_id};
        my $negLog10p = $row{neg_log10_p};
        my @values = split /\t/, $line;

        if (exists $geneSummary->{$targetGene}) {
            my $hitCount = $geneSummary->{$targetGene}->{hitCount};

            if ($negLog10p > $geneSummary->{$targetGene}->{p}) {
                $geneSummary->{$targetGene} = {
                    p => $negLog10p,
                    hit => \@values,
                    hitCount => ++$hitCount
                };
                # $self->log("DEBUG: New best hit: " . Dumper($geneSummary->{$targetGene}));
            }

            else {
                $geneSummary->{$targetGene}->{hitCount} = ++$hitCount;
            }
        }
        else {
            $geneSummary->{$targetGene} = { 
                p => $negLog10p,
                hit => \@values,
                hitCount => 1
            };
            # $self->log("DEBUG: First hit: " . Dumper($geneSummary->{$targetGene}));
        }
    }
    
    return $geneSummary;
}
   

sub cleanFile {
    my ($self, $file, $workingDir) = @_;

    my $inputFileName = File::Spec->catfile($workingDir, $self->getArg('sourceId') . "-temp-input.txt");
    open( my $pfh, '>', $inputFileName ) || $self->error("Unable to create sharded input file $inputFileName for writing");
    $pfh->autoflush(1);
    print $pfh join( "\t", @INPUT_FIELDS) . "\n";

    my $fh = undef;
    $self->log("INFO: Processing file $file.");
    if ($file =~ m/\.gz$/) {
         open($fh, "zcat $file |")  || $self->error("Can't open gzipped $file.");
    }
    else {
        open ($fh, $file) || $self->error("Can't open $file.");
    }

    my $header = <$fh>;
    chomp($header);
    my @fields = split /\t/, $header;
    my %columns = map { $fields[$_] => $_ } 0 .. $#fields;
      
    # process the file
    my $lineCount = 0;
    my $skipCount = 0;

    while (my $line = <$fh>) {
        chomp $line;

        my @values = split /\t/, $line;

        #TODO: replace with @values{@EXPECTEDFIELDS} = split /\t/, $line; 
        # so we can use field names instead of indexes

        my $skip = 0;

        if ($values[4] == 0) { # pvalue
            $skipCount++;
            next;
        }

        my $chromosome = $values[0]; #chrom
        $chromosome =~ s/chr//g;

        my $position   = $values[2]; # chromEnd

        my $metaseqId = $values[3]; # variant_id
        my $marker = undef;
        if ($metaseqId =~ /rs/) {
            $marker = $metaseqId;
            # 6,7 are ref, alt respectively
            $metaseqId = join(':', ($chromosome, $position, $values[6], $values[7]));
        }
        else {
            $metaseqId =~ s/chr//g;
        }

        my $rv = {
            chromosome => $chromosome,
            position   => $position,
            marker     => $marker,
            metaseq_id => $metaseqId,
            ref => $values[6],
            alt => $values[7]
        };

        $self->writeCleanedInput($pfh, $rv, \%columns, @values ) 
            if (!$skip);

        if ( ++$lineCount % 500000 == 0 ) {
            $self->log("INFO: Cleaned $lineCount lines");
        }
    }

    $self->log("INFO: Cleaned $lineCount lines");
    $self->log("INFO: Skipped $skipCount lines due to missing or invalid information.");

    $pfh->close();
    $fh->close();

    return $inputFileName;
}


sub writeCleanedInput {
    my ( $self, $fh, $resultVariant, $fields, @values ) = @_;

    my ( $pvalue, $negLog10p, $displayP ) =
      $self->formatPvalue( $values[4] );

    my $otherStats = $self->buildOtherStatsJson(@values);

    my $distToTarget = $values[16];
    if ($distToTarget == '.') {
        $distToTarget = "NULL";
    }

    my $targetGene = $values[9];
    $targetGene =~ s/\|/;/g;

# qw(#chrom chromStart chromEnd variant_id pval target_strand ref alt target_gene_symbol target_ensembl_id target z_score_non_ref beta_non_ref beta_se_non_ref FDR non_ref_af qtl_dist_to_target QC_info target_info user_input);
# qw(chr bp ref alt marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json)
    print $fh join(
        "\t",
        (
            $resultVariant->{chromosome},
            $resultVariant->{position},
            $resultVariant->{ref},
            $resultVariant->{alt},
            $resultVariant->{marker} ? $resultVariant->{marker} : "NULL",
            $resultVariant->{metaseq_id},
            $pvalue,
            $negLog10p,
            $displayP,
            $targetGene,
            $distToTarget,
            $otherStats
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



sub buildOtherStatsJson {
    my ( $self, @values ) = @_;
    my $stats = {};
    while ( my ( $stat, $index ) = each %OTHER_STATS_FIELD_MAP ) {
        my $tValue = lc( $values[$index] );
        if ( $tValue eq "infinity" or $tValue =~ m/^inf$/ ) {
            $stats->{$stat} = "Infinity";
        }
        else
        { # otherwise replaces Infinity w/inf which will cause problems w/load b/c inf s not a number in postgres
            my $cValue = $values[$index];
            $cValue =~ s/"//g;
            $cValue =~ s/\|/;/g;
            $stats->{$stat} = Utils::toNumber( $cValue );
        }
    }
    return Utils::to_json($stats);
}

# ----------------------------------------------------------------------
# clean and sort
# ----------------------------------------------------------------------

 
# ----------------------------------------------------------------------
sub undoTables {
    my ($self) = @_;

    $self->log('To UNDO: run PGUndo plugin with the option: `--undoTables Results.QTLGene`');
    return ();
}
1;
