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
    my $tid = threads->tid();

    my $sess = $self->initSnmpSession($hashRef);
    return undef if not defined($sess);

    print STDOUT "[$tid][$hashRef->{name}] Get SNMP VarList (ip $hashRef->{ip})\n";
    nimLog(2, "[$tid][$hashRef->{name}] Get SNMP VarList (ip $hashRef->{ip})");
    my @result = $sess->get(['sysObjectID', 0]);

    if(scalar(@result) != 1) {
        print STDOUT "[$tid][$hashRef->{name}] Failed to get SNMP systemVarList\n";
        nimLog(2, "[$tid][$hashRef->{name}] Failed to get SNMP systemVarList");
        return undef;
    }

    return {
        sysObjectID => $result[0]
    };
}

sub initSnmpSession {
    my ($self, $hashRef) = @_;
    my $tid = threads->tid();

    print STDOUT "[$tid][$hashRef->{name}] Open SNMP Session, ip $hashRef->{ip}\n";
    nimLog(3, "[$tid][$hashRef->{name}] Open SNMP Session, ip $hashRef->{ip}");
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