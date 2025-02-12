## $Id: LoadQTLResult.pm $
##
package GenomicsDBData::GWAS::Plugin::LoadQTLResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;

use GUS::PluginMgr::Plugin;
use GUS::Model::Results::QTL;
use GUS::Model::Study::ProtocolAppNode;

BEGIN { $Package::Alias::BRAVE = 1 }
use Package::Alias Utils            => 'GenomicsDBData::Load::Utils';
use Package::Alias PluginUtils      => 'GenomicsDBData::Load::PluginUtils';

use JSON::XS;
use Data::Dumper;
use File::Spec;

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
  qw(chr bp allele1 allele2 marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json);


my $COPY_SQL = <<COPYSQL;
COPY Results.QTL(
protocol_app_node_id,
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
'Loads  QTL result in multiple passes: 1) generate input file that can be passed on to DB mapping scripts; 2) load a result';

    my $tablesAffected =
      [ [ 'Results::QTL', 'Enters a row for each feature' ]];

    my $tablesDependedOn =
      [ [ 'Study::ProtocolAppNode', 'lookup analysis source_id' ] ];

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
            cvsRevision       => '$Revision: 4$',
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
            allele1 => $values[6],
            allele2 => $values[7]
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
    $self->log("INFO: Loading GWAS summary statistics into Results.QTL");

    my ($v, $workingDir, $f) = File::Spec->splitpath($self->getArg('file'));
    my $inputFileName = File::Spec->catfile($workingDir, 'preprocess', $self->getArg('sourceId') . "-input.txt.map");
    $self->log("INFO: Loading from file: $inputFileName");

    open(my $fh, $inputFileName) || $self->error("Unable to open $inputFileName for reading");

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
        if ($row{pvalue} eq 'NULL') {  
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
    $self->log("WARNING - SKIPPED: $unmappedSkipCount Results not mapped to the database.");
}

# ----------------------------------------------------------------------
# helper methods
# ----------------------------------------------------------------------

sub processArgs {
    my ($self) = @_;

    my $preprocess = $self->getArg('preprocess');

    if (!$preprocess) {
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
    # $self->log("DEBUG: " . Dumper($data));

    my @values = (
        $self->{protocol_app_node_id}, $recordPK,
        $binIndex, 'chr' . $data->{chr},
        $data->{bp}, $data->{allele2}, $data->{neg_log10_p},
        $data->{display_p}, $data->{target_ensembl_id},
        $data->{dist_to_target}, $data->{other_stats_json}        
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
# qw(chr bp allele1 allele2 marker metaseq_id pvalue neg_log10_p display_p target_ensembl_id dist_to_target other_stats_json)
    print $fh join(
        "\t",
        (
            $resultVariant->{chromosome},
            $resultVariant->{position},
            $resultVariant->{allele1},
            $resultVariant->{allele2},
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

    $self->log('To UNDO: run PGUndo plugin with the option: `--undoTables Results.QTL`');
    return ();
}
1;
