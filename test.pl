use strict;
use POSIX;
use threads;
use Thread::Queue;
use threads::shared;
use Data::Dumper;

use Net::SNMP;

my ($session, $error) = Net::SNMP->session(
    -hostname => "75.2.31.28",
    -port => "161",
    -version => "3",
    -timeout => "30",
    -retries => "3",
    -username => "TEST",
    -authpassword => "PW",
    -authprotocol => "sha",
    -privpassword => "PW",
    -privprotocol => "aes"
);
die $error if $error ne "";

# my %defaultOID = (
#     sysDesc => '1.3.6.1.2.1.1.1.0',
#     sysObjectID => '1.3.6.1.2.1.1.2.0',
#     sysUpTime => '1.3.6.1.2.1.1.3.0',
#     sysContact => '1.3.6.1.2.1.1.4.0',
#     sysName => '1.3.6.1.2.1.1.5.0',
#     sysLocation => '1.3.6.1.2.1.1.6.0',
#     sysServices => '1.3.6.1.2.1.1.7.0'
# );

# my $sysResult = $session->get_request(-varbindlist => [ 
#     $defaultOID{sysDesc},
#     $defaultOID{sysObjectID},
#     $defaultOID{sysUpTime},
#     $defaultOID{sysContact},
#     $defaultOID{sysName},
#     $defaultOID{sysLocation},
#     $defaultOID{sysServices}
# ]);

# my $sysResult = $session->get_request(-varbindlist => [ 
#     '.1.3.6.1.2.1.1.5'
# ]);

# if(!defined($sysResult)) {
#     print "result not defined! \n";
#     print $session->error();
#     $session->close();
#     exit(0);
# }

# print Dumper($sysResult)."\n";

my $oidTest = $session->get_table( -baseoid => '.1.3.6.1.4.1.6527.3.1.2.11.1.3' );
print Dumper($oidTest);