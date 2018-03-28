package src::snmpmanager;

# Perl Core package(s)
use strict;
use Data::Dumper;

# Third-party packages(s)
use SNMP;
&SNMP::addMibDirs("/opt/nimsoft/MIBS");
&SNMP::loadModules("ALL");
&SNMP::initMib();
$SNMP::use_sprint_value = 1;

# Nimsoft package(s)
use Nimbus::API;

# Core packages
use src::utils;

# Snmpmanager Prototype Constructor
sub new {
    my ($class) = @_;
    return bless({}, ref($class) || $class);
}

# @subroutine snmpSysInformations
# @desc Get NOKIA Router system informations !
# @memberof snmpManager
# @param {HashReference} hashRef
# @return {HashReference}
sub snmpSysInformations {
    my ($self, $hashRef) = @_;

    my $sess = $self->initSnmpSession($hashRef);
    return undef if not defined($sess);
    my $vars = new SNMP::VarList(
        ['sysDescr', 0], 
        ['sysObjectID', 0],
        ['sysUpTime', 0],
        ['sysContact', 0],
        ['sysName', 0],
        ['sysLocation', 0],
        ['sysServices', 0]
    );
    my @request_result = $sess->get($vars);
    if(scalar(@request_result) == 0) {
        print STDOUT "Failed to get SNMP systemVarList with hostname $hashRef->{name}, ip $hashRef->{ip}\n";
        nimLog(2, "Failed to get SNMP systemVarList with hostname $hashRef->{name}, ip $hashRef->{ip}");
        return undef;
    }

    return {
        sysDesc     => $request_result[0],
        sysObjectID => $request_result[1],
        sysUpTime   => $request_result[2],
        sysContact  => $request_result[3],
        sysName     => $request_result[4],
        sysLocation => $request_result[5],
        sysServices => $request_result[6]
    };
}

sub initSnmpSession {
    my ($self, $hashRef) = @_;
    print STDOUT "Create new SNMP Session for hostname $hashRef->{name}, ip $hashRef->{ip}\n";
    nimLog(3, "Create new SNMP Session for hostname $hashRef->{name}, ip $hashRef->{ip}");

    my $sess = new SNMP::Session(
        DestHost    => $hashRef->{ip},
        Version     => $hashRef->{snmp_version},
        SecName     => $hashRef->{username},
        AuthProto   => $hashRef->{auth_protocol},
        AuthPass    => $hashRef->{auth_key},
        PrivProto   => $hashRef->{priv_protocol},
        PrivPass    => $hashRef->{priv_key},
        Timeout     => 1000000,
        Retries     => 2,
        SecLevel    => "authPriv"
    );
    if(!defined($sess)) {
        print STDOUT "Failed to initialize SNMP session with hostname $hashRef->{name}, ip $hashRef->{ip}\n";
        nimLog(2, "Failed to initialize SNMP session with hostname $hashRef->{name}, ip $hashRef->{ip}");
        return undef;
    }
    return $sess;
}

1;