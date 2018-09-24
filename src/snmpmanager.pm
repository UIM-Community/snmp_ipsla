package src::snmpmanager;

# Perl Core package(s)
use strict;

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
    my $tid = threads->tid();

    my $sess = $self->initSnmpSession($hashRef);
    return undef if not defined($sess);

    print STDOUT "[$tid][$hashRef->{name}] Get SNMP VarList (ip $hashRef->{ip})\n";
    nimLog(2, "[$tid][$hashRef->{name}] Failed to get SNMP systemVarList (ip $hashRef->{ip})");
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
    nimLog(2, "[$tid][$hashRef->{name}] ".Dumper(@request_result));

    if(scalar(@request_result) == 0) {
        print STDOUT "[$tid][$hashRef->{name}] Failed to get SNMP systemVarList (ip $hashRef->{ip})\n";
        nimLog(2, "[$tid][$hashRef->{name}] Failed to get SNMP systemVarList (ip $hashRef->{ip})");
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
    my $tid = threads->tid();

    print STDOUT "[$tid] Open SNMP Session on hostname $hashRef->{name}, ip $hashRef->{ip}\n";
    nimLog(3, "[$tid] Open SNMP Session on hostname $hashRef->{name}, ip $hashRef->{ip}");
    my $sess = new SNMP::Session(
        DestHost    => $hashRef->{ip},
        Version     => $hashRef->{snmp_version},
        SecName     => $hashRef->{username},
        AuthProto   => $hashRef->{auth_protocol},
        AuthPass    => $hashRef->{auth_key},
        PrivProto   => $hashRef->{priv_protocol},
        PrivPass    => $hashRef->{priv_key},
        Timeout     => 1000000,
        Retries     => 3,
        SecLevel    => "authPriv"
    );
    if(!defined($sess)) {
        print STDOUT "[$tid] Failed to initialize SNMP session on hostname $hashRef->{name}, ip $hashRef->{ip}.\n";
        nimLog(2, "[$tid] Failed to initialize SNMP session on hostname $hashRef->{name}, ip $hashRef->{ip}.");
        return undef;
    }
    return $sess;
}

1;