#!/does/not/exist/but/fools/vim/perl
# WeSQL application configuration file
# Do not edit unless you know what you are doing!

# This file is part of the Sample Addressbook application
# shipped with WeSQL v0.50
# For more information see http://wesql.org

# You will need to restart the web server after changing
# this file.

@commandlist = ( 
      'dolayouttags($body)',
      'dosubst($body,"PR_",%params)',
      'dosubst($body,"ENV_",%ENV)',
      'dosubst($body,"COOKIE_",%cookies)',
      'doeval($body,"PRE")',
      'doinsert($body)',
      'doeval($body,"POSTINSERT")',
      'doparamcheck($body)',
      'docutcheck($body)',
      'doeval($body,"PRELIST")',
      'dolist($body,$dbh)',
      'doeval($body,"POST")',
      'docutcheck($body)'
      );

# For MySQL:
$dbtype = 0;
$dsn = "DBI:mysql:database=addressbook;host=localhost";

# For PostgreSQL:
#$dbtype = 1;
#$dsn = "DBI:Pg:dbname=addressbook;host=localhost";

$dbuser = "root";
$dbpass = "test";

# Set this to zero to disable authentication. Note that jform.wsql and jdeleteform.wsql will NOT work.
# They need to store session data (editdest, canceldest, deldest), but there is no session when you're 
# not logged in...
$authenticate = 1;

# $authsuperuserdir MUST start and end with a / !!
# $authsuperuserdir MUST be defined before $noauthurls!
$authsuperuserdir = "/admin/";
# Add urls that need no authentication, separate them with a pipe-symbol, and make sure they start with a forward slash!
$noauthurls = "\/jlogin.wsql|\/jloginform.wsql|\/jlogout.wsql|$authsuperuserdir\Ljlogout.wsql|$authsuperuserdir\Ljloginform.wsql|$authsuperuserdir\Ljlogin.wsql";
# Set $authsuperuser to 1 if you want a superuser directory
$authsuperuser = 1;
