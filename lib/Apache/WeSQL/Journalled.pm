package Apache::WeSQL::Journalled;

use 5.006;
use strict;
use warnings;
use lib(".");
use lib("../");

use Apache::WeSQL;
use Apache::WeSQL::SqlFunc qw(:all);

use Apache::Constants qw(:common);

use CGI;

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 'all' => [ qw(
	readConfigFile jAdd jUpdate jDelete jAddPrepare jUpdatePrepare jDeletePrepare jErrorMessage 
	sWrite sDelete sRead sReadAll sOverWrite sDeleteValue
	operaBugDecode operaBugEncode
) ] );
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
our @EXPORT = qw( );

our $VERSION = '0.50';

############################################################
# The code for storing and retrieving session-data starts here
# Prerequisite: a table like the following in your database (this is the MySQL definition):
# (for the PostgreSQL definition see the sample Addressbook application)
#create table sessiondata (
#  pkey bigint(20) unsigned not null auto_increment,
#  id bigint(20) unsigned not null,
#
#  uid bigint(20) unsigned not null,
#  suid bigint(20) unsigned not NULL default '0',
#  epoch bigint unsigned not null,
#  status tinyint default '1' NOT NULL,
#
#  loginid bigint(20) unsigned not null,
#  name varchar(50) default '' not null,
#  value varchar(255) default '' not null,
#  primary key (pkey)
#);
#
############################################################

############################################################
# sWrite
# sWrite is short for session-write, and can add a piece of information,
# described by a key and a value, to the session.
############################################################
sub sWrite {
	my ($dbh,$key,$value) = @_;
	# Now first get the id of the login (effectively, the id of this session)
	my $id = $Apache::WeSQL::cookies{id};
	$id = $Apache::WeSQL::cookies{su} if (defined($Apache::WeSQL::cookies{su}));
	my @login = &sqlSelect($dbh,"select id from logins where userid='$id' and hash='$Apache::WeSQL::cookies{hash}' and status='1'");
	my @columns = ('name','value','loginid');
	my @values = ($key,$value,$login[0]);
	&Apache::WeSQL::log_error("$$: sWrite: add '$key' -> '$value' to session data for login $login[0]") if ($Apache::WeSQL::DEBUG);
	&jAdd($dbh,"sessiondata",\@columns,\@values,"id");
}

############################################################
# sOverWrite
# sOverWrite is short for session-overwrite.
# It writes a key/value pair to the session, but overwrites any existing value for this key.
############################################################
sub sOverWrite {
	my ($dbh,$key,$value) = @_;
	&sDelete($dbh,$key);
	&sWrite($dbh,$key,$value);
}

############################################################
# sRead
# sRead is short for session-read, and will return 1 value for a specified key,
# if stored in the session. Returns undef if there is no such key in the session.
# The optional parameter $sort determines whether the last (default) or the first
# ($sort = 1) value should be returned, if there is more than one key with this
# name.
############################################################
sub sRead {
	my ($dbh,$key,$sort) = @_;
	$sort ||= 0;
	# Now first get the id of the login (effectively, the id of this session)
	my $id = $Apache::WeSQL::cookies{id};
	$id = $Apache::WeSQL::cookies{su} if (defined($Apache::WeSQL::cookies{su}));
	my @login = &sqlSelect($dbh,"select id from logins where userid='$id' and hash='$Apache::WeSQL::cookies{hash}' and status='1'");
	# And then retrieve the data
	my @result = &sqlSelect($dbh,"select value from sessiondata where loginid='$login[0]' and name='$key' and status='1' order by id " . ($sort == 1?"DESC":""));
	&Apache::WeSQL::log_error("$$: sRead: read session data '$key' for login $login[0], " . ($sort == 1?"last added value":"oldest value")) if ($Apache::WeSQL::DEBUG);
	return undef if ($#result == -1);
	return $result[0];
}

############################################################
# sReadAll
# sRead is short for session-read-all, and will return all values for a specified key,
# if stored in the session. Returns undef if there is no such key in the session.
# The optional parameter $sort determines whether the sorting should be LIFO or FIFO,
# if there is more than one key with this name.
############################################################
sub sReadAll {
	my ($dbh,$key,$sort) = @_;
	$sort ||= 0;
	# Now first get the id of the login (effectively, the id of this session)
	my $id = $Apache::WeSQL::cookies{id};
	$id = $Apache::WeSQL::cookies{su} if (defined($Apache::WeSQL::cookies{su}));
	my @login = &sqlSelect($dbh,"select id from logins where userid='$id' and hash='$Apache::WeSQL::cookies{hash}' and status='1'");
	# And then retrieve the data
	my $c = &sqlSelectMany($dbh,"select value from sessiondata where loginid='$login[0]' and name='$key' and status='1' order by id " . ($sort == 1?"DESC":""));
	&Apache::WeSQL::log_error("$$: sReadAll: read session data '$key' for login $login[0], order" . ($sort == 1?"LIFO":"FIFO")) if ($Apache::WeSQL::DEBUG);
	return $c;
}

############################################################
# sDelete
# sDelete is short for session-delete, and can delete 1 piece of information,
# described by a key, from a session. Returns the value of the deleted key, so you
# can use sDelete as a 'shift' or 'pop' function.
# Returns undef when no matching key was found.
############################################################
sub sDelete {
	my ($dbh,$key,$sort) = @_;
	$sort ||= 0;
	# Now first get the id of the login (effectively, the id of this session)
	my $id = $Apache::WeSQL::cookies{id};
	$id = $Apache::WeSQL::cookies{su} if (defined($Apache::WeSQL::cookies{su}));
	my @login = &sqlSelect($dbh,"select id from logins where userid='$id' and hash='$Apache::WeSQL::cookies{hash}' and status='1'");
	# Now get the id of the key to delete
	my @result = &sqlSelect($dbh,"select id,value from sessiondata where loginid='$login[0]' and name='$key' and status='1' order by id " . ($sort == 1?"DESC":""));
	if ($Apache::WeSQL::DEBUG) {
		if ($#result > -1) {
			&Apache::WeSQL::log_error("$$: sDelete: delete '$key' with id '$result[0]' from session data for login $login[0]");
		} else {
			&Apache::WeSQL::log_error("$$: sDelete: '$key' for login $login[0] does not exist");
		}
	}
	return undef if ($#result == -1);
	&jDelete($dbh,"sessiondata","name='$key' and id='$result[0]'");
	return ($result[1]);
}

############################################################
# sDeleteValue
# sDeleteValue is short for session-delete-value, and can delete 1 piece of information,
# described by a key and its value, from a session. 
############################################################
sub sDeleteValue {
	my ($dbh,$key,$value) = @_;
	# Now first get the id of the login (effectively, the id of this session)
	my @login = &sqlSelect($dbh,"select id from logins where userid='$Apache::WeSQL::cookies{id}' and hash='$Apache::WeSQL::cookies{hash}' and status='1'");
	&Apache::WeSQL::log_error("$$: sDeleteValue: delete '$key' with value '$value' from session data for login $login[0]") if ($Apache::WeSQL::DEBUG);
	&jDelete($dbh,"sessiondata","name='$key' and value='$value'");
}

############################################################
# The code for storing and retrieving session-data ends here
############################################################

############################################################
# jAdd
# Adds a record in a journalled database
# parameter 1: $dbh: database handler
# parameter 2: $table: database table
# parameter 3: \@columns: columns
# parameter 4: \@values: values
# parameter 5: $toincrement: column to increment (must be of a numeric type!)
# parameter 6: $uid: user id	(optional, defaults to the value of the cookie uid, if any)
# parameter 7: $suid: superuser id (optional, defaults to the value of the cookie suid, if any)
############################################################
sub jAdd {
	my ($dbh,$table,$colref,$valref,$toincrement,$uid,$suid) = @_;
	my $nextval = "";
	$uid ||= $Apache::WeSQL::cookies{id};
	$suid ||= $Apache::WeSQL::cookies{su};
	$uid ||= 0;
	$suid ||= 0;

  # Determine the database type
  my $dbtype = 0; #MySQL
  $dbtype = 1 if (${$dbh}->{Driver}->{Name} =~ /^Pg/);
	
	if (defined($toincrement)) {
		&sqlGeneric($dbh,"lock tables $table write") if ($dbtype == 0); #No locking necessary for PostGreSQL!
		my @r = &sqlSelect($dbh,"select max($toincrement) from $table");
		$r[0] ||= 0;		# In case there are no records in this table
		$nextval = $r[0] + 1;	#Assuming that the $toincrement column is numeric!!! Not FOOLPROOF!
		push(@{$colref},('epoch','status','uid','suid',$toincrement));
		push(@{$valref},(time(),'1',$uid,$suid,$nextval));
	} else {
		push(@{$colref},('epoch','status','uid','suid',));
		push(@{$valref},(time(),'1',$uid,$suid));
	}

	&jDebugInfo("jAdd",$colref,$valref) if ($Apache::WeSQL::DEBUG);

	my $pkey = &sqlInsertReturn($dbh,$table,$colref,$valref,"pkey");
	if (!defined($pkey)) {
		&sqlGeneric($dbh,"unlock tables") if (defined($toincrement) && ($dbtype == 0));
		&Apache::WeSQL::log_error("$$: jAdd: could not add record to table $table");
		return ($nextval,"Could not add record to table '$table'. Try again!");
	}
	&sqlGeneric($dbh,"unlock tables") if (defined($toincrement) && ($dbtype == 0));
	return ($nextval,"");
}

############################################################
# jDebugInfo
# Helper sub for jAdd and jUpdate
# Prints debug information to the server's log
############################################################
sub jDebugInfo {
	my ($subname,$colref,$valref,$extra1,$extra2) = @_;
	$extra1 ||= "";
	$extra2 ||= "";
	my $logstr = "$$: $subname: $extra1(";
	for (my $cnt=0; $cnt<=$#{$valref};$cnt++) {
		my $tmp = "${$colref}[$cnt]='${$valref}[$cnt]'";
		$tmp = substr($tmp,0,100); #Chop off after 100 chars to keep logs readable
		$logstr .= "$tmp,";
	}
	chop($logstr); 
	$logstr .= ")$extra2";
	&Apache::WeSQL::log_error($logstr);
}

############################################################
# jUpdate
# Updates a record in a journalled database
# parameter 1: $dbh: database handler
# parameter 2: $table: database table
# parameter 3: \@columns: columns
# parameter 4: \@values: values
# parameter 5: $where: condition of the sql query
# parameter 6: $uid: user id	(optional, defaults to the value of the cookie uid, if any, or else to 0)
# parameter 7: $suid: superuser id (optional, defaults to the value of the cookie suid, if any, or else to 0)
# parameter 8: $pkey: name of the autoincrement column, (optional, defaults to 'pkey')
############################################################
sub jUpdate {	
	my ($dbh,$table,$colref,$valref,$where,$uid,$suid,$pkey) = @_;
	$pkey ||= 'pkey';
	$uid ||= $Apache::WeSQL::cookies{id};
	$suid ||= $Apache::WeSQL::cookies{su};
	$uid ||= 0;
	$suid ||= 0;

	my $dbtype = 0; #MySQL
	$dbtype = 1 if (${$dbh}->{Driver}->{Name} =~ /^Pg/);

	# Get all the names of the columns
	my ($colarrayref,$colhashref) = &buildColumnList($dbh,$table);

	&jDebugInfo("jUpdate",$colref,$valref,"update $table set "," where $where") if ($Apache::WeSQL::DEBUG);

	# Get the records to process
	my $c = &sqlSelectMany($dbh,"SELECT * FROM $table WHERE $where and status='1'");

	# Disable the existing records
	if (!defined(&sqlUpdate($dbh,$table,"status='0'","$where"))) {
		&Apache::WeSQL::log_error("$$: jUpdate: could not disable (a) record(s) in table $table");
		return "Could not disable (a) record(s) in table '$table'. Try again!";
	}
	my $sth = &sqlPrepareInsert($dbh,$table,@{$colarrayref});

	my $pgpkey;
	if ($dbtype == 1) {	#PostgreSQL
		my @tmp = &sqlSelect($dbh,"select nextval('$table\L_$pkey\L_seq')");
		$pgpkey = $tmp[0];
	}

	# And insert new ones, one by one
	while (my @values = $c->fetchrow()) {
		if ($dbtype == 0) { #MySQL
			$values[${$colhashref}{$pkey}] = '';
		} else { #PostgreSQL
			# This is a good example where PostgreSQL SUCKS. If you give MySQL nothing for the value of an 'autoincrement', 
			# it is smart enough to actually 'auto-increment'. But these 'sequences' in PostgreSQL are too dumb for that. They think '' means 0.
			# So it works the first time and the next time you get 'can't insert duplicate key'. Hence this workaround. Bloody stupid.
			$values[${$colhashref}{$pkey}] = $pgpkey++;
		}
		$values[${$colhashref}{uid}] = $uid;
		$values[${$colhashref}{suid}] = $suid;
		$values[${$colhashref}{epoch}] = time();
		for (my $cnt=0;$cnt<=$#{$colref};$cnt++) {
			$values[${$colhashref}{${$colref}[$cnt]}] = ${$valref}[$cnt];
		}

		&sqlExecuteInsert($dbh,$sth,@values);
	}
	return "";
}

############################################################
# jDelete
# Disables a record in a journalled database
# parameter 1: $dbh: database handler
# parameter 2: $table: database table
# parameter 3: $where: condition of the sql query
# parameter 4: $uid: user id	(optional, defaults to the value of the cookie uid, if any)
# parameter 5: $suid: superuser id (optional, defaults to the value of the cookie suid, if any)
# parameter 6: $pkey: name of the autoincrement column, defaults to 'pkey'
############################################################
sub jDelete { 
	my ($dbh,$table,$where,$uid,$suid,$pkey) = @_;
	$pkey ||= "pkey";

	$uid ||= $Apache::WeSQL::cookies{id};
	$suid ||= $Apache::WeSQL::cookies{su};
	$uid ||= 0;
	$suid ||= 0;

	my @cols = ('status');
	my @vals = ('0');
	
	&Apache::WeSQL::log_error("$$: jDelete: update $table set (status='0') where $where") if ($Apache::WeSQL::DEBUG);

	if (!defined(&jUpdate($dbh,$table,\@cols,\@vals,$where,$uid,$suid,$pkey))) {
		&Apache::WeSQL::log_error("$$: jDelete: could not disable (a) record(s) in table $table");
		return "Could not disable a record in table '$table'. Try again!";
	}
	return "";
}

############################################################
# buildColumnList
# This sub returns a reference to an array and to a hash with 
# the names of columns, ordered as the database returns them. 
# The value of the hash keys is the number of the column, the 
# value of the array entries is obviously the column name.
# parameter 1: $dbh: database handler
# parameter 2: $table: database table
############################################################
sub buildColumnList { 
	my $dbh = shift;
	my $table = shift;
	my @columns;
	my %columns;

	my $sql = "";

	# Determine the database type
	my $dbtype = 0; #MySQL
	$dbtype = 1 if (${$dbh}->{Driver}->{Name} =~ /^Pg/);

	if ($dbtype == 0) { #MySQL
		$sql = "SHOW COLUMNS FROM $table";
	} elsif ($dbtype == 1) { #PostgreSQL
		$sql = "SELECT a.attname, t.typname, a.attlen, a.atttypmod, a.attnotnull, \
						a.atthasdef, a.attnum FROM pg_class c, pg_attribute a, pg_type t \
						WHERE c.relname = '$table' AND a.attnum > 0 AND a.attrelid = c.oid \
						AND a.atttypid = t.oid ORDER BY a.attnum";
	}
	my $c = &sqlSelectMany($dbh,$sql);

	if (defined($c)) {
		my $cnt = 0;
		my ($colname);
		$c->bind_col(1, \$colname);
		while ($c->fetch) {
			$columns{$colname} = $cnt;
			$columns[$cnt++] = $colname;
		}
		$c->finish();
                
		return \@columns, \%columns;
  }
  return undef, undef;
}

############################################################
# Code for the /add, /delete and /update urls
############################################################

############################################################
# readConfigFile
# Processes files like 'permissions' and returns a hash containing
# the information from the requested section (the '$view' parameter)
# of the file.
############################################################
sub readConfigFile {
	my $file = shift;
	my $view = shift;
	my %data = ();
	my $r = Apache->request;
	# Get the 'base-uri' from the request: for instance, for /admin/jlist that would be /admin/, and for /jlist that would just be /
	my $uri = $r->uri;
	my ($baseuri) = ($uri =~ /^(.+)\//);
	$baseuri .= '/';
	&Apache::WeSQL::log_error("$$: Journalled.pm: readConfigFile: opening $file with baseuri $baseuri and uri: " . $r->uri) if ($Apache::WeSQL::DEBUG);
	if (!defined(open(DEFINITIONS,$r->document_root . $baseuri . "$file"))) {
		&Apache::WeSQL::log_error("$$: Journalled.pm: readConfigFile: file '" . $r->document_root . "$baseuri\L$file' not found!");
		&jErrorMessage("Configuration file not found! Please contact the webmaster.","Can't read $file!");
		exit;
	}
	my $gatheredinfo = join("",<DEFINITIONS>);
	close(DEFINITIONS);
	&Apache::WeSQL::log_error("$$: Journalled.pm: readConfigFile: file '$baseuri\L$file' succesfully read (view: $view)") if ($Apache::WeSQL::DEBUG);
	my @views = split(/\n\n/,$gatheredinfo);
	foreach (@views) {
		my @lines = split(/\n/,$_);
		my $name = "";
		while (($name eq "") && ($#lines > -1)) {
			$name = shift @lines; #First line should contain nothing but the name of the view
		}
		return %data if ($#lines < 0);	#Bail out if end of file reached
		if ($view ne $name) { next; }
		my %count;
		foreach (@lines) {
			my ($type, $body) = split(/:/,$_,2);
			if (lc($type) eq "inherit") { #inherit will overwrite any earlier definitions!!
				%data = &readConfigFile($file,$body);
			} elsif (lc($type) =~ /^(captions|align)$/) {	# For jList, jDetails and jForm
				my @pairs = split(/\|/,$body);
				foreach (@pairs) {
					my ($column,$title) = split("=",$_);
		  		$data{lc($type) . ".$column"} = $title;
				}
			} elsif (lc($type) =~ /^(replace|form)$/) {	# 'replace' for jList and jDetails, 'form' for jForm
				my ($param1, $param2) = split(/=/,$body,2);
				$data{lc($type) . ".$param1"} = $param2;
			} elsif (lc($type) =~ /^(sqlcondition|sqlconditiontext|validate|validateif|validateifcondition|validatetext|validateiftext)/) {	# For jValidate/jForm only
				if (!defined($count{lc($type)})) { 
					$count{lc($type)} = 1; 
				} else { 
					$count{lc($type)}++; 
				}
				$data{lc($type) . "." . $count{lc($type)}} = $body;
			} else {
				$data{lc($type)} = $body;
			}
		}
	}
	foreach (keys %data) {
		# Replace %data variables with their values!
		# Replace %params and %cookies variables with their values!
		# Note that we allow shorthand %cookies and %params in the '.cf' file
		# The encode() command will url-encode the enclosed value. See the man page describing the .cf files
		my $key = $_;
		$data{$key} =~ s/\$data{(.*?)}/$data{$1}/eg;
		$data{$key} =~ s/\[(.*?)encode\(\$params{(.*?)}\)(.*?)(?<!\\)\|(.*?)\]/(defined($Apache::WeSQL::params{$2}) && ($Apache::WeSQL::params{$2} ne '')?"$1" . operaBugEncode(CGI::escape($Apache::WeSQL::params{$2})) . "$3":"$4")/eg;
		$data{$key} =~ s/\[(.*?)\$params{(.*?)}(.*?)(?<!\\)\|(.*?)\]/(defined($Apache::WeSQL::params{$2}) && ($Apache::WeSQL::params{$2} ne '')?"$1$Apache::WeSQL::params{$2}$3":"$4")/eg;
		$data{$key} =~ s/encode\(\$params{(.*?)}\)/(defined($Apache::WeSQL::params{$1})?operaBugEncode(CGI::escape($Apache::WeSQL::params{$1})):'')/eg;

		$data{$key} =~ s/\[(.*?)decode\(\$params{(.*?)}\)(.*?)(?<!\\)\|(.*?)\]/(defined($Apache::WeSQL::params{$2}) && ($Apache::WeSQL::params{$2} ne '')?"$1" . operaBugDecode(CGI::escape($Apache::WeSQL::params{$2})) . "$3":"$4")/eg;
		$data{$key} =~ s/\[(.*?)\$params{(.*?)}(.*?)(?<!\\)\|(.*?)\]/(defined($Apache::WeSQL::params{$2}) && ($Apache::WeSQL::params{$2} ne '')?"$1$Apache::WeSQL::params{$2}$3":"$4")/eg;
		$data{$key} =~ s/decode\(\$params{(.*?)}\)/(defined($Apache::WeSQL::params{$1})?operaBugDecode(CGI::escape($Apache::WeSQL::params{$1})):'')/eg;

		$data{$key} =~ s/\$params{(.*?)}/(defined($Apache::WeSQL::params{$1})?$Apache::WeSQL::params{$1}:'')/eg;
		$data{$key} =~ s/\$cookies{(.*?)}/(defined($Apache::WeSQL::cookies{$1})?$Apache::WeSQL::cookies{$1}:'')/eg;
		$data{$key} =~ s/\[(.*?)\$cookies{(.*?)}(.*?)(?<!\\)\|(.*?)\]/(defined($Apache::WeSQL::cookies{$2}) && ($Apache::WeSQL::cookies{$2} ne '')?"$1$Apache::WeSQL::cookies{$2}$3":$4)/eg;
		$data{$key} =~ s/dest=caller/"dest=" . operaBugEncode(CGI::escape($r->uri . "?" . $r->args))/eg;
	}
	# If we didn't find any data for this view, abort and flag this in the logs!
	if (scalar keys %data == 0) {
		&jErrorMessage("Journalled.pm: readConfigFile: View not found. Please contact the webmaster.","view '$view' not found in " . $r->document_root . "/$file");
		exit;
	}
	return %data;
}

############################################################
# operaBugEncode
# operaBugDecode
# There is a bug in Opera 5.05 for Linux (and possibly in more versions),
# where url-encoded parts of urls are decoded when they shouldn't be.
# So we do some 'custom' encoding here, replacing %26 (the code for &)
# by ____, which stops Opera from decoding the whole string.
# I've posted a bug report with Opera on 2001.11.07, and also posted
# a description of the problem on the opera.tech newsgroup at news.opera.com
# An Opera developer acknowledged the problem and fixed it, the fix will most 
# likely be in the next release.
############################################################
sub operaBugEncode {
	my $toenc = shift;
	$toenc =~ s/%26/____/g;
	return $toenc;
}

sub operaBugDecode {
	my $todec = shift;
	# Try to be a bit clever about when to replace the %26 with ____ or &
	if ($todec =~ /\%/) {
		$todec =~ s/____/%26/g;
	} else {
		$todec =~ s/____/\&/g;
	}
	return $todec;
}

############################################################
# jErrorMessage
# Builds & logs an error message
############################################################
sub jErrorMessage {
	my ($message,$logmessage,$printheader) = @_;
	$printheader = 1 if (!defined($printheader));
	&Apache::WeSQL::log_error("$$: jErrorMessage: $logmessage");
  my $dd = localtime();
	print <<"EOF" if ($printheader);
HTTP/1.1 200 OK
Date: $dd
Server: Apache
Connection: close
Content-type: text/html

EOF

print <<"EOF";
<html>
<head><title>Error</title></head>
<body bgcolor=#FFFFFF>
<h1>Error</h1>
$message
<hr>
This page was dynamically generated by <a href=http://wesql.org>WeSQL</a>
</body>
</html>
EOF
	exit;
}

############################################################
# htmlStrip
# strips html and newlines from a passed string and returns the 'clean' string
############################################################
sub htmlStrip {
	my $tostrip = shift;
	$tostrip =~ s/\<.*?\>//g;
	$tostrip =~ s/\n/ +++ /g;
	return $tostrip;
}

############################################################
# jValidate
# Processes the 'validate', 'validateif', and 'sqlcondition' tags
# from the 'permissions.cf' file
############################################################
sub jValidate {
	my ($dbh,$type,%data) = @_;
	my $retval = "";
	my ($colarrayref,$colhashref) = &buildColumnList($dbh,$data{table});
	# First the 'validate' rules!
	for (my $cnt = 1; $cnt < 101; $cnt++) {
		last if (!defined($data{"validate.$cnt"}));
		if (!(eval($data{"validate.$cnt"}))) {
			$data{"validatetext.$cnt"} ||= '<font color=#FF0000>A condition has not been met!</font><br>';
			$retval .= $data{"validatetext.$cnt"};
		}
		&Apache::WeSQL::log_error("$$: Journalled.pm: jValidate: validate EVAL error: " . $@) if $@;  
	}
	# Then the 'validateif' rules!
	for (my $cnt = 1; $cnt < 101; $cnt++) {
		last if (!defined($data{"validateif.$cnt"}));
		# Check if the validateif condition has been met!
		if (eval($data{"validateifcondition.$cnt"})) {
			if (!(eval($data{"validateif.$cnt"}))) {
				$data{"validateiftext.$cnt"} ||= '<font color=#FF0000>A condition has not been met!</font><br>';
      	$retval .= $data{"validateiftext.$cnt"};
    	}
		}
		&Apache::WeSQL::log_error("$$: Journalled.pm: jValidate: validateif EVAL error: " . $@) if $@;  
	}
	# And finally the 'sqlcondition' rules!
	for (my $cnt = 1; $cnt < 101; $cnt++) {
		last if (!defined($data{"sqlcondition.$cnt"}));
		$data{"sqlconditiontext.$cnt"} ||= "<center><font color=#FF0000>This action can not be allowed.</font></center><br>";

		my ($action,$left,$operator,$right) = split(/\|/,$data{"sqlcondition.$cnt"},4);
		next if (!(lc($action) =~ /$type/));	# This sqlCondition doesn't apply to the type of action

		my (@r1,@r2) = ((),());
		if ($left =~ /select/) {
			my $r1 = &sqlGeneric($dbh,$left);
			@r1 = $r1->fetchrow();
			$r1[0] = "'$r1[0]'";	#Make sure the output from the query is properly quoted as it will be eval'ed below!
			$r1->finish();
		} else {
			$r1[0] = $left;				# Proper quoting is the users responsibility here...
		}
		if ($right =~ /select/) {
			my $r2 = &genericQuery($dbh,$right);
			@r2 = $r2->fetchrow();
			$r2[0] = "'$r2[0]'";	#Make sure the output from the query is properly quoted as it will be eval'ed below!
			$r2->finish();
		} else {
			$r2[0] = $right;				# Proper quoting is the users responsibility here...
		}
		my $condition = "return ($r1[0] $operator $r2[0]?1:0)";
		
		my $returnvalue = eval $condition;
		&Apache::WeSQL::log_error("$$: Journalled.pm: jValidate: eval error: condition: $condition gives error: " . $@) if $@;
		$retval .= $data{"sqlconditiontext.$cnt"} if (!$returnvalue);
	}
	&jErrorMessage($retval . "<p>Please use the <b>back</b> button of your browser and try again", "jValidate: view $Apache::WeSQL::params{view}: ". htmlStrip($retval)) if ($retval ne '');
}

############################################################
# jPrepareTest
# Sub called by jAddPrepare, jDeletePrepare and jUpdatePrepare
# Does some basic tests on the "permissions.cf" file, and on the
# parameters passed to the script.
############################################################
sub jPrepareTest {
	my $dbh = shift;
	my $type = shift;
	my $view = $Apache::WeSQL::params{view};
	my $redirdest;
	if ($type eq 'delete') {
		$redirdest = &sRead($dbh,"deldest$view");
	} else {
		$redirdest = &sRead($dbh,"editdest$view");
	}
	my %data = &readConfigFile("permissions.cf",$view);

	# We need to have:
	#		redirdest	(stored in session data)
	#		view
	#		(any names & values of fields that must be initialised with a value upon adding the record)

	&jErrorMessage("Error on the server, contact the webmaster.","jPrepareTest: redirdest not defined") if (!defined($redirdest));
	&jErrorMessage("Error on the server, contact the webmaster.","jPrepareTest: view not defined") if (!defined($Apache::WeSQL::params{view}));
	&jErrorMessage("Error on the server, contact the webmaster.","jPrepareTest: table not defined") if (!defined($data{table}));
	&jErrorMessage("Error on the server, contact the webmaster.","jPrepareTest: increment not defined") if (!defined($data{increment}));
	&jErrorMessage("Error on the server, contact the webmaster.","jPrepareTest: $type not defined in data hash") if (!defined($data{$type}));

	&jErrorMessage("You are not allowed to do this. Go Away.","jPrepareTest: illegal attempt to change data in view $view, type $type") if ((lc($data{$type}) ne "yes") && ($type ne "update"));
	&jValidate($dbh,$type,%data) if ($type ne "delete");	# No validate and other fancy stuff in permissions.cf for deleting!

	# Form's been validated, remove the destinations in the database!
	if ($type eq 'delete') {
		&sDelete($dbh,"deldest$view");
	} else {
		&sDelete($dbh,"editdest$view");
	}

	delete($Apache::WeSQL::params{view});
	return($view,$redirdest,%data);
}

############################################################
# jAddPrepare
# Translates a request to /add into a request that jAdd can understand,
# provided all prerequisites have been fulfilled (like the appropriate
# lines in the 'permissions.cf' file, and the appropriate parameters
# passed)
############################################################
sub jAddPrepare {
	my $dbh = shift;
	# There is a bug in Exporter.pm that doesn't allow us to do a 'circular' export:
	# We export some symbols from WeSQL to WeSQL::Journalled
	# Try to export some symbols from WeSQL::Journalled to WeSQL at the same time.
	# You will be able to access the exported symbols from WeSQL::Journalled in WeSQL, but not
	# the symbols from WeSQL exported to WeSQL::Journalled. Weird.
	# Of course we can still access the symbols through their fully qualified name.
	# WVW, 25.10.2001	ward@pong.be

	my ($view,$redirdest,%data) = jPrepareTest($dbh,"add");

	my (@columns,@values);
	foreach (keys %Apache::WeSQL::params) {
		next if ($_ eq "epoch");
		next if ($_ eq "status");
		next if ($_ eq "uid");
		next if ($_ eq "suid");
		push(@columns,$_);
		push(@values,$Apache::WeSQL::params{$_});
	}
	&jAdd($dbh,$data{table},\@columns,\@values,$data{increment});
	&Apache::WeSQL::redirect($redirdest);
}

############################################################
# jDeletePrepare
# Translates a request to /delete into a request that jDelete can understand,
# provided all prerequisites have been fulfilled (like the appropriate
# lines in the 'permissions.cf' file, and the appropriate parameters
# passed)
############################################################
sub jDeletePrepare {
	my $dbh = shift;

	my ($view,$deldest,%data) = jPrepareTest($dbh,"delete");

	if (defined($Apache::WeSQL::params{cancel}) && ($Apache::WeSQL::params{cancel} eq "Cancel")) {
		my $canceldest = &sDelete($dbh,"canceldest$view");
		&sDelete($dbh,"deldest$view");	# Delete the deldest, we won't need that anymore!
		&Apache::WeSQL::redirect($canceldest);
	}

	# No id number given!
#	if (!defined($Apache::WeSQL::params{$data{increment}})) {
	&jErrorMessage("Error on the server, contact the webmaster.","jDeletePrepare: id to delete not defined") if (!defined($Apache::WeSQL::params{$data{increment}}));
#		my $body = jError();
#		return ($body,0);
#	}

	&jDelete($dbh,$data{table},"$data{increment}=$Apache::WeSQL::params{$data{increment}}");
	&sDelete($dbh,"canceldest$view"); # Delete the canceldest, we won't need that anymore!
	&sDelete($dbh,"editdest$view"); # Delete the editdest for this view, we won't need that anymore!
	&Apache::WeSQL::redirect($deldest);
}

############################################################
# jUpdatePrepare
# Translates a request to /update into a request that jUpdate can understand,
# provided all prerequisites have been fulfilled (like the appropriate
# lines in the 'permissions.cf' file, and the appropriate parameters
# passed)
############################################################
sub jUpdatePrepare {
	my $dbh = shift;

	my ($view,$redirdest,%data) = jPrepareTest($dbh,"update");

	my @updateable_cols = split(/\,/,$data{update});
	my %updateable_cols;
	foreach (@updateable_cols) {
		$updateable_cols{$_} = $_;
	}
	
	my (@columns,@values);
	foreach (keys %Apache::WeSQL::params) {
		next if ($_ eq "epoch");
		next if ($_ eq "status");
		next if ($_ eq "uid");
		next if ($_ eq "suid");
		if (defined($updateable_cols{$_})) {
			push(@columns,$_);
			push(@values,$Apache::WeSQL::params{$_});
		}
	}

	# No id number given!
#	if (!defined($Apache::WeSQL::params{$data{increment}})) {
#		my $body = jError();
	&jErrorMessage("Error on the server, contact the webmaster.","jUpdatePrepare: id to update not defined") if (!defined($Apache::WeSQL::params{$data{increment}}));
#		return ($body,0);
#	}

	&jUpdate($dbh,$data{table},\@columns,\@values,
			"$data{increment}=$Apache::WeSQL::params{$data{increment}}");
	&Apache::WeSQL::redirect($redirdest);
}

############################################################
# End of code for the /jadd.wsql, /jdelete.wsql and /jupdate.wsql urls
############################################################

1;
__END__

=head1 NAME

Apache::WeSQL::Journalled - A library of functions to deal with an SQL database 
in a Journalled way.

=head1 SYNOPSIS

  use Apache::WeSQL::Journalled qw( :all );

=head1 DESCRIPTION

This module contains all functions necessary to deal with SQL databases in a Journalled way.
You may call them directly from any WeSQL document, however, they will probably mostly be
used by direct webcalls to jadd.wsql, jdelete.wsql or jmodify.wsql, with the appropriate parameters and
configuration in the 'permissions.cf' file. And, of course, in the form.cf file. For more information on the format of these .cf files, see L<Apache::WeSQL::Display>.

For the journalling code to work, every table will need to have the following additional fields (MySQL definition):
(for the PostgreSQL definition see the sample Addressbook application)

        pkey bigint(20) unsigned not null auto_increment,
        id bigint(20) unsigned not null,

        uid bigint(20) unsigned not null,
        suid bigint(20) unsigned not NULL default '0',
        epoch bigint unsigned not null,
        status tinyint default '1' NOT NULL,

In addition to that, the 'pkey' column must be defined as the primary key:

        primary key (pkey)

The underlying idea is that with the Journalling code, records are never (NEVER!) deleted from the database. Instead, when a record needs to be changed, its status is set to '0', and its data is copied to a new record with status '1' and changed. When a record needs to be deleted, its status is set to '0'. 

This allows tracing all changes to the data in your database. Of course, when the database becomes too big, you can occasionally backup and delete all records with status='0'.

When the authentication has not been switched off, the userid (and possibly superuser-id) of the person doing the change is recorded in the uid and suid fields. Superusers can 'cloak' themselves to be an ordinary user. This means that when they change a record, the uid will be the id of the ordinary user, thus maintaining the ownership of the record, but the suid will be the id of the superuser.

The columns have the following functions:

=over 4

=item *
pkey: The primary key. This value is unique in the table.

=item *
id: The key, identifying unique records. There can be only 1 record with status='1' for any give value of id.

=item *
uid: The user id of the user who created/changed this record. This is used to determine who 'owns' a record.

=item *
suid: The superuser id of the superuser who created/changed this record. Zero for records without superuser intervention.

=item *
epoch: The exact date & time of the last change to the record, in seconds since January 1st 1970.

=item *
status: 1 or 0, active or not active.

=back

Of course, for all this business with users and logging in to work, you will need the following two tables in your database (MySQL definitions):
(for the PostgreSQL definition see the sample Addressbook application)

    create table logins (
      pkey bigint(20) unsigned not null auto_increment,
      id bigint(20) unsigned not null,

      uid bigint(20) unsigned not null,
      suid bigint(20) unsigned not NULL default '0',
      epoch bigint unsigned not null,
      status tinyint default '1' NOT NULL,

      userid bigint(20) unsigned not null,
      hash varchar(16) default '' not null,
      primary key (pkey)
    );

    create table users (
      pkey bigint(20) unsigned not null auto_increment,
      id bigint(20) unsigned not null,

      uid bigint(20) unsigned not null,
      suid bigint(20) unsigned not NULL default '0',
      epoch bigint unsigned not null,
      status tinyint default '1' NOT NULL,
      active tinyint default '1' NOT NULL,

      login varchar(50) default '' not null,
      password varchar(50) default '' not null,
      superuser tinyint default '0' NOT NULL,
      primary key (pkey)
    );

=head1 SESSION DATA

This module also contains some code for storing and retrieving data in a user session. This code is used by the jform, jdetails and jlist code in the Apache::WeSQL::Display module. It needs a table called 'sessiondata' in your database, which is defined as follows (MySQL definition):
(for the PostgreSQL definition see the sample Addressbook application)

    create table sessiondata (
      pkey bigint(20) unsigned not null auto_increment,
      id bigint(20) unsigned not null,

      uid bigint(20) unsigned not null,
      suid bigint(20) unsigned not NULL default '0',
      epoch bigint unsigned not null,
      status tinyint default '1' NOT NULL,

      loginid bigint(20) unsigned not null,
      name varchar(50) default '' not null,
      value varchar(255) default '' not null,
      primary key (pkey)
    );

The subs for reading/writing/deleting session data are: sWrite sDelete sRead sReadAll sOverWrite sDeleteValue. You can use these in EVAL blocks in wesql files.
For more information, have a look at the source code of the Apache::WeSQL::Journalling module.

=head1 EXPORT

None by default. Possible: 
	readConfigFile jAdd jUpdate jDelete jAddPrepare jUpdatePrepare jDeletePrepare jErrorMessage 
	sWrite sDelete sRead sReadAll sOverWrite sDeleteValue
	operaBugDecode operaBugEncode

=head1 AUTHOR

Ward Vandewege, E<lt>ward@pong.beE<gt>

=head1 SEE ALSO

L<Apache::WeSQL>, L<Apache::WeSQL::SqlFunc>, L<Apache::WeSQL::Display>, L<Apache::WeSQL::Auth>, L<Apache::WeSQL::AppHandler>

=cut
