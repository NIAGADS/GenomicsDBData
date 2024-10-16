package GenomicsDBData::Load::PluginUtils;

use GUS::Model::Study::ProtocolAppNode;
use GUS::Model::Study::Study;

use JSON::XS;

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

sub getHouseKeepingSql {
  return $HOUSEKEEPING_FIELDS;
}

sub buildHouseKeepingString {
  my ($plugin) = @_;

  my $algInvId = $plugin->getAlgInvocation()->getId();
  my $rowUserId = $plugin->getAlgInvocation()->getRowUserId();
  my $rowGroupId = $plugin->getAlgInvocation()->getRowGroupId();
  my $rowProjectId = $plugin->getAlgInvocation()->getRowProjectId();
  my $housekeeping = join('|',
			  1, 1, 1, 1, 1, 0,
			  $rowUserId, $rowGroupId,
			  $rowProjectId, $algInvId);
  return $housekeeping;
}

sub bulkCopy {
  my ($plugin, $buffer, $copySql) = @_;

  my $dbh = $plugin->getDbHandle();
  $dbh->do($copySql); # puts database in copy mode; no other trans until finished
  $dbh->pg_putcopydata($buffer);
  $dbh->pg_putcopyend() || $plugin->error($dbh->errstr);
  $plugin->getDbHandle()->commit() if $plugin->getArg('commit'); # commit
}

sub generateUpdatedJsonFromGusObj {
  my ($plugin, $gusObj, $field, $newJsonObj) = @_;
  # if newJsonObj is not undef, returns newJsonObj || oldJsonObj, otherwise
  # returns old, which may also be null
  my $oldJsonStr = $gusObj->get($field);
  my $jsonObj = JSON::XS->new;
  $jsonObj = $jsonObj->decode($oldJsonStr) || $plugin->error("Error parsing JSON: $oldJsonStr");
  if ($newJsonObj) {
    $jsonObj = {%$jsonObj, %$newJsonObj};
  }
  return $jsonObj;
}


# takes an id and prepared query hand and returns a single value
sub fetchValueById {
  my ($id, $qh) = @_;
  $qh->execute($id);
  my ($value) = $qh->fetchrow_array();
  return $value;
}

sub setDirectoryPermissions {
  my ($plugin, $directory, $permissions) = @_;
  `chmod $permissions -R $directory`;
  $plugin->log("Updated directory permissions for $directory to $permissions");
}

sub createDirectory {
  my ($plugin, $path, $dirName) = @_;

  my $fullPath = $path . "/" . $dirName;
  $fullPath =~ s/\/\//\//g; # substitute // for /

  if (-e $fullPath) {
    $plugin->log("WARNING: Directory $fullPath already exists");
  }
  else {
    mkdir $fullPath or $plugin->error("Error creating directory: $fullPath");
    $plugin->log("Created directory: $fullPath");
  }

  return $fullPath;
}

sub fileExists {
  my ($plugin, $file) = @_;
  return 1 if (-e $file);
  return 0;
}


sub getProtocolAppNodeId {
  my ($plugin, $sourceId) = @_;
  my $protocolAppNode = GUS::Model::Study::ProtocolAppNode
    ->new({source_id => $sourceId});
  $plugin->error("No protocol app node found for $sourceId")
    unless $protocolAppNode->retrieveFromDB();

  return $protocolAppNode->getProtocolAppNodeId();
}

sub getStudyId {
  my ($plugin, $sourceId) = @_;
  my $study = GUS::Model::Study::Study
    ->new({source_id => $sourceId});
  $plugin->error("No study found for $sourceId")
    unless $study->retrieveFromDB();

  return $study->getStudyId();
}


# ----------------------------------------------------------------------
# # check whether result from sql function is null
# ----------------------------------------------------------------------
sub isNull {
  my ($response) = @_;
  return 1 if (!$response or $response eq '');
  return 0;
}

1;
