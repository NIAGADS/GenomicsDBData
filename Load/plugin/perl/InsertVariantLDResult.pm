## InsertVariantLDResult.pm.pm
## $Id: InsertVariantLDResult.pm.pm $
##

package GenomicsDBData::Load::Plugin::InsertVariantLDResult;
@ISA = qw(GUS::PluginMgr::Plugin);

use strict;
use GUS::PluginMgr::Plugin;
use POSIX qw(strftime);

use Data::Dumper;

use GUS::Model::Results::VariantLD;
use GUS::Model::Study::ProtocolAppNode;

use Bio::DB::HTS::Tabix;

my $HOUSEKEEPING_FIELDS =<<HOUSEKEEPING;
modification_date,
user_read,
user_write,
group_read,
group_write,
other_read,
other_write,
row_user_id,
row_group_id,
row_project_id,
row_alg_invocation_id
HOUSEKEEPING

my $COPY_SQL=<<SQL;
COPY Results.VariantLD (
population_protocol_app_node_id,
chromosome,
locations,
minor_allele_frequency,
distance,
r,
r_squared,
d_prime,
$HOUSEKEEPING_FIELDS
)
FROM STDIN 
WITH (DELIMITER '|', 
NULL 'NULL')
SQL

# ----------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------

sub getArgumentsDeclaration {
  my $argumentDeclaration  =
    [
     stringArg({name => 'dir',
		descr => 'directory containing LD output (gz/tbi pairs)',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     stringArg({name => 'sourceId',
		descr => 'protocol app node source id',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),
     stringArg({name => 'skipChr',
		descr => 'skip the specified chromosome(s)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	   }),

     stringArg({name => 'onlyChr',
		descr => 'only do the specified chromosome(s)',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	       }),

     stringArg({name => 'chromosome',
		descr => 'column name containing chromosome info',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

      stringArg({name => 'position1',
		descr => 'column name containing first position',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
		}),


     stringArg({name => 'position2',
		descr => 'column name containing second position',
		constraintFunc=> undef,
		reqd  => 1,
		isList => 0
	       }),

     stringArg({name => 'maf1',
		descr => 'column name containing first minor allele frequency Value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
		}),

     
     stringArg({name => 'maf2',
		descr => 'column name containing second minor allele frequency Value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
		}),
     
     stringArg({name => 'rSquared',
		descr => 'column name containing R Squared Value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
		}),

     stringArg({name => 'r',
		descr => 'column name containing R Value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
	       }),

      stringArg({name => 'dPrime',
		descr => 'column name containing D Prime Value',
		constraintFunc=> undef,
		reqd  => 0,
		isList => 0
		}),

      stringArg({name => 'filter',
		 descr => 'stat|value filter (e.g., rSquared|0.2 will remove results w/rSquared <= 0.2)',
		 default =>  'rSquared|0.2',
		 constraintFunc=> undef,
		 reqd  => 0,
		 isList => 0
	       }),

    ];
  return $argumentDeclaration;
}

# ----------------------------------------------------------------------
# Documentation
# ----------------------------------------------------------------------

sub getDocumentation {
  my $purposeBrief = 'Loads Variant LD result';

  my $purpose = 'Loads Variant LD result';

  my $tablesAffected = [['Results::VariantLD', 'Enters a row for each variant feature']];

  my $tablesDependedOn = [['Study::ProtocolAppNode', 'lookup analysis source_id']];

  my $howToRestart = '';

  my $failureCases = '';

  my $notes = <<NOTES;

NOTE: requires input file to bgzipped and tab-indexed

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
  my @skipChrms = ($self->getArg('skipChr')) ? $self->parseChrms($self->getArg('skipChr')) : undef;
  my @onlyChrms = ($self->getArg('onlyChr')) ? $self->parseChrms($self->getArg('onlyChr')) : undef;

  $self->{protocol_app_node_id} = $self->getProtocolAppNodeId();

  $self->validateArgs();
  $self->setFilter();

  my @files = $self->getFiles();
  my $processFiles;
  foreach my $f (@files) {
    if ($self->getArg('skipChr')) {
      $self->log(Dumper(\@skipChrms));
      if ($self->matchChrms($f, @skipChrms)) {
	$self->log("WARNING: Skipping $f");
	next;
      }
      $processFiles->{$f} = 1;
    }
    if ($self->getArg('onlyChr')) {
      unless ($self->matchChrms($f, @onlyChrms)) {
	$self->log("WARNING: Skipping $f");
	next;
      }
      $processFiles->{$f} = 1;
    }
  }

  my @pfiles = sort keys %$processFiles; 
  $self->log("INFO: Processing " . scalar @pfiles . " files:");
  $self->log("INFO: " . Dumper(\@pfiles));
  foreach my $f (@pfiles) {
    $self->log("INFO: Processing $f");
    $self->copy($f);
  }
}

# ----------------------------------------------------------------------
# methods called by run
# ----------------------------------------------------------------------

sub matchChrms {
  my ($self, $fileName, @chrms) = @_;
  foreach my $c (@chrms) {
    return 1 if ($fileName =~ /\Q$c/); # return when matched
  }
  return 0; # no match
}

sub parseChrms {
  my ($self, $chrStr) = @_;
  my @chrms = split /,/, $chrStr;
  for my $i (0 .. $#chrms) {
    if ($chrms[$i] !~ m/chr/) {
      $chrms[$i] = 'chr' . $chrms[$i] . ".";
    }
    else {
      $chrms[$i] .= ".";
    }
  }
  return @chrms;
}

sub setFilter {
  my ($self) = @_;
  my $filterStr = $self->getArg('filter');
  my ($field, $threshold) = split /\|/, $filterStr;
  if ($field eq 'rSquared') {
    $self->{filters}->{r_squared} = $threshold;
  }
  else {
    $self->error("Filter not yet implemented for $field");
  }
}

sub validateArgs {
  my ($self) = @_;

  if (!$self->getArg('r') && !$self->getArg('rSquared') && !$self->getArg('dPrime')) {
    $self->error("Must supply field name for at least one of the following statistics: R, rSquared, dPrime");
  }
  if ((!$self->getArg('maf1') && $self->getArg('maf2')) || ($self->getArg('maf1') && !$self->getArg('maf2'))) {
    $self->error("Must suppply MAF for both variants (maf1 & maf2)");
  }
}

sub getFiles {
  my ($self) = @_;

  my $dir = $self->getArg('dir');
  $self->log("INFO: Fetching files from: $dir");
  opendir(DIR, $dir);
  my @files = grep(/chr.*\.gz$/,readdir(DIR));
  closedir(DIR);
  $self->log("INFO: Found " . scalar @files . " files.");
  return @files;
}

sub buildInsertStr {
  my ($self, $fieldMap, @lineValues) = @_;

  my @insertValues;
  my $chrm = $lineValues[$fieldMap->{chromosome}];
  $chrm =~ s/MT/M/g;
  if ($chrm =~ m/chr/) {
    push(@insertValues, $chrm)
  }
  else {
    push(@insertValues, 'chr' . $chrm);
  }
  
  my @locations = ($lineValues[$fieldMap->{location1}], $lineValues[$fieldMap->{location2}]);
  push(@insertValues, '{' . join(',', @locations) . '}');

  if ($self->getArg('maf1')) {
    my @mafs = ($lineValues[$fieldMap->{maf1}], $lineValues[$fieldMap->{maf2}]);
    push(@insertValues, '{' . join(',', @mafs) . '}');
  }
  else {
    push(@insertValues, 'NULL');
  }

  my $distance = abs($locations[0] - $locations[1]);
  push(@insertValues, $distance);

  if ($self->getArg('r')) {
    push(@insertValues, $lineValues[$fieldMap->{r}])
  }
  else {
    push(@insertValues, 'NULL')
  }

  if ($self->getArg('rSquared')) {
    my $rsq = $lineValues[$fieldMap->{r_squared}];
    if (exists $self->{filters}->{r_squared}) {
      return undef if ($rsq < $self->{filters}->{r_squared});
    }
    push(@insertValues, $rsq);
  }
  else {
    push(@insertValues, 'NULL')
  }

   if ($self->getArg('dPrime')) {
    push(@insertValues, $lineValues[$fieldMap->{d_prime}])
  }
  else {
    push(@insertValues, 'NULL')
  }

  return join('|', @insertValues);
}


sub buildFieldMap {
  my ($self, $header) = @_;
  my @columns = split /\t/, $header;
  my %columnMap = map { $columns[$_] => $_ } 0..$#columns;


  my $fieldMap = {chromosome => $columnMap{$self->getArg('chromosome')},
		  location1 => $columnMap{$self->getArg('position1')},
		  location2 => $columnMap{$self->getArg('position2')}
		 };

  if ($self->getArg('maf1')) {
    $fieldMap->{maf1} = $columnMap{$self->getArg('maf1')};
    $fieldMap->{maf2} = $columnMap{$self->getArg('maf2')};
  }

  $fieldMap->{r_squared} = $columnMap{$self->getArg('rSquared')} if $self->getArg('rSquared');
  $fieldMap->{r} = $columnMap{$self->getArg('r')} if $self->getArg('r');
  $fieldMap->{d_prime} = $columnMap{$self->getArg('dPrime')} if $self->getArg('dPrime');

  return $fieldMap;
}

sub isValidTabixRegion {
  my ($self, $tabix, $region) = @_;
  my $rowCount = 0;
  my $iter = $tabix->query($region);
  eval {
    while (my $line = $iter->next ) {
      ++$rowCount;
      last;
    }
  };
  return ($rowCount > 0);
}

sub getTabixIterator {
  my ($self, $tabixFileName, $tabix, $region) = @_;
  
  my $testRegion = $region;
  my $isValid = $self->isValidTabixRegion($tabix, $testRegion);

  if (!$isValid) {
    if ($testRegion =~ m/chr/) {
      $testRegion =~ s/chr//g;
    }
    else {
      $testRegion = 'chr' . $testRegion;
    }
  }

  $isValid = $self->isValidTabixRegion($tabix, $testRegion);

  $self->error("Unable to find $region or $testRegion in tabix file: $tabixFileName")
    if (!$isValid);
  
  return $tabix->query($testRegion);
}

sub copy {
  my ($self, $file) = @_;

  my $filePath = $self->getArg('dir') . "/" . $file;
  my $tabix = Bio::DB::HTS::Tabix->new(filename => $filePath, use_tmp_dir => 0) || $self->error("Unable to read $file - $!");
  my $fieldMap = $self->buildFieldMap($tabix->header);

  $file =~ m/(chrX|chrY|chrMT|chr\d+)/;
  my $chromosome = $1;
  # $chromosome = 'chrM' if $chromosome =~ m/MT/;

  my $protocolAppNodeId = $self->{protocol_app_node_id};
  my $algInvId = $self->getAlgInvocation()->getId();
  my $rowUserId = $self->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $self->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $self->getAlgInvocation()->getRowProjectId();
  my $housekeeping = join('|', 	  getCurrentTime(),
			  1, 1, 1, 1, 1, 0,
			  $rowUserId, $rowGroupId,
			  $rowProjectId, $algInvId);

  my $dbh = $self->getDbHandle();
  $dbh->do($COPY_SQL); # puts database in copy mode; no other trans until finished

  my $count = 0;

  my $iter = $self->getTabixIterator($filePath, $tabix, $chromosome);
  my $skipCount = 0;
  while (my $line = $iter->next) {
    my @values = split /\t/, $line;
    my $fieldValues = $self->buildInsertStr($fieldMap, @values);
    if (!$fieldValues) {
      $skipCount++;
      next;
    }
    
    $dbh->pg_putcopydata($protocolAppNodeId . "|" . $fieldValues . "|" . $housekeeping . "\n");
    unless (++$count % 1000000) {
      $dbh->pg_putcopyend();   # end copy trans can no do other things
      $self->getDbHandle()->commit() if $self->getArg('commit'); # commit
      $self->log("Inserted $count records.");
      $dbh->do($COPY_SQL); # puts database in copy mode; no other trans until finished
    }
  }
  $dbh->pg_putcopyend();       # end copy trans can no do other things
  $self->getDbHandle()->commit() if $self->getArg('commit'); # commit
  $self->log("Inserted $count records.");
  $self->log("Skipped $skipCount records that failed to meet filtering criteria: " . $self->getArg('filter'));
  $tabix->close();
}


# ----------------------------------------------------------------------
# supporting methods
# ----------------------------------------------------------------------


sub getProtocolAppNodeId {
  my ($self) = @_;
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $self->getArg('sourceId')});
  $self->error("No protocol app node found for " . $self->getArg('sourceId'))
    unless $protocolAppNode->retrieveFromDB();
  return $protocolAppNode->getProtocolAppNodeId();
}

sub getCurrentTime {
  return strftime '"%Y-%m-%d %H:%M:%S"', localtime;
}

# ----------------------------------------------------------------------
#sub undoTables {
#  my ($self) = @_;
#  return ('Results.VariantLD');
#}



1;
