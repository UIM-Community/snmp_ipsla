package src::snmpmanager;

# Perl Core package(s)
use strict;
use Data::Dumper;

# Third-party packages(s)
use SNMP;

# Nimsoft package(s)
use Nimbus::API;

# Snmpmanager Prototype Constructor
sub new {
    my ($class) = @_;
    return bless({}, ref($class) || $class);
}

# @subroutine ascii_oid
# @desc Transform oid indexes into a complete string
# @param {!String} oid
# @param {Integer=} mode
# @returns {String}
sub ascii_oid($$) {
    my ($oid, $mode) = @_;
    my $temptmp='';
    my @comb;
    foreach my $c (split(/\./, $oid)) {
        if ($c > 31 && $c < 127) {
            $temptmp .= chr($c);
        }
        else {
            push @comb, $temptmp if $temptmp ne '';
            push @comb, int($c) if $mode==1;
            $temptmp = '';
        }
    }

    # Final push if something is not pushed already
    push @comb, $temptmp if $temptmp ne '';
    $temptmp = join(".", @comb);

    # clean generated ASCII text
    $temptmp =~ s/"/\\"/go;
    $temptmp =~ s/^[.]?(.*?)[.]?$/$1/o;
    return $temptmp;
}

# @subroutine snmpSysInformations
# @desc Get NOKIA Router system informations !
# @memberof snmpManager
# @param {HashReference} hashRef
# @return {HashReference}
sub snmpSysInformations {
    my ($self, $hashRef) = @_;
    print STDOUT "Create new SNMP Session for hostname $hashRef->{ip}\n";
    nimLog(3, "Create new SNMP Session for hostname $hashRef->{ip}");

    my $sess = new SNMP::Session(
        DestHost    => $hashRef->{ip},
        Version     => $hashRef->{snmp_version},
        Timeout     => 1000000,
        Retries     => 2,
        SecName     => $hashRef->{username},
        SecLevel    => "authPriv",
        AuthProto   => $hashRef->{auth_protocol},
        AuthPass    => $hashRef->{auth_key},
        PrivProto   => $hashRef->{priv_protocol},
        PrivPass    => $hashRef->{priv_key}
    );
    if(!defined($sess)) {
        print STDOUT "Failed to initialize SNMP session with hostname $hashRef->{ip}\n";
        nimLog(2, "Failed to initialize SNMP session with hostname $hashRef->{ip}");
        return undef;
    }

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
        print STDOUT "Failed to get SNMP systemVarList with hostname $hashRef->{ip}\n";
        nimLog(2, "Failed to get SNMP systemVarList with hostname $hashRef->{ip}");
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

1;