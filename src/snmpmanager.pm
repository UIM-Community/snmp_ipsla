package src::snmpmanager;

# Perl Core package(s)
use strict;
use Data::Dumper;
use Net::SNMP;

my %SYS_INFO_OIDS = (
    sysDesc => '1.3.6.1.2.1.1.1.0',
    sysObjectID => '1.3.6.1.2.1.1.2.0',
    sysUpTime => '1.3.6.1.2.1.1.3.0',
    sysContact => '1.3.6.1.2.1.1.4.0',
    sysName => '1.3.6.1.2.1.1.5.0',
    sysLocation => '1.3.6.1.2.1.1.6.0',
    sysServices => '1.3.6.1.2.1.1.7.0'
); 

sub oidsToArray {
    my ($hash) = @_;
    my @ret = ();
    push(@ret, $_) for values %{ $hash };
    return \@ret;
}

# Snmpmanager Prototype Constructor
sub new {
    my ($class) = @_;
    return bless({}, ref($class) || $class);
}

sub snmpSysInformations {
    my ($self, $hashRef) = @_;
    print STDOUT "ip => $hashRef->{ip}\n";
    my ($session, $error) = Net::SNMP->session(
        -hostname => $hashRef->{ip},
        -port => "161",
        -version => $hashRef->{snmp_version},
        -timeout => "2",
        -retries => "1",
        -username => $hashRef->{username},
        -authpassword => $hashRef->{auth_key},
        -authprotocol => $hashRef->{auth_protocol},
        -privpassword => $hashRef->{priv_key},
        -privprotocol => $hashRef->{priv_protocol}
    );

    if($error ne "") {
        print STDERR "$error\n";
        return;
    }

    my $request_result = $session->get_request(-varbindlist => [ 
        $SYS_INFO_OIDS{sysDesc},
        $SYS_INFO_OIDS{sysObjectID},
        $SYS_INFO_OIDS{sysUpTime},
        $SYS_INFO_OIDS{sysContact},
        $SYS_INFO_OIDS{sysName},
        $SYS_INFO_OIDS{sysLocation},
        $SYS_INFO_OIDS{sysServices}
    ]);
    return {
        sysDesc     => $request_result->{$SYS_INFO_OIDS{sysDesc}},
        sysObjectID => $request_result->{$SYS_INFO_OIDS{sysObjectID}},
        sysUpTime   => $request_result->{$SYS_INFO_OIDS{sysUpTime}},
        sysContact  => $request_result->{$SYS_INFO_OIDS{sysContact}},
        sysName     => $request_result->{$SYS_INFO_OIDS{sysName}},
        sysLocation => $request_result->{$SYS_INFO_OIDS{sysLocation}},
        sysServices => $request_result->{$SYS_INFO_OIDS{sysServices}}
    } if defined($request_result);

    my $requestError = $session->error();
    print STDERR "$requestError\n";
    $session->close();
    return;
}