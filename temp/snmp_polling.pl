use SNMP;
use strict;
use warnings;
use Data::Dumper;

&SNMP::addMibDirs("/tmp/MIBS");
&SNMP::loadModules("ALL");
&SNMP::initMib();
$SNMP::use_sprint_value = 1;

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

# # # Init session !
my $sess = new SNMP::Session(
    DestHost => "75.2.1.27",
    Version => 3,
    Timeout => 1000000,
    Retries => 1,
    SecName => "SIC-Manager",
    SecLevel => "authPriv",
    AuthProto => "SHA",
    AuthPass => "SIC-SCR-AUTH",
    PrivProto => "AES",
    PrivPass => "SIC-SCR-PRIV"
);

# my $oid = &SNMP::translateObj('tmnxOamPingCtlTable');
my $oid = &SNMP::translateObj('tmnxOamPingResultsTable');
my $hash = $sess->gettable($oid, nogetbulk => 1);
print Dumper($hash);
foreach(keys %{ $hash }) {
    $hash->{ascii_oid($_, 0)} = $hash->{$_};
    delete $hash->{$_};
}
print Dumper($hash);