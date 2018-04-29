package src::utils;

# Perl Core package(s)
use strict;
use Exporter qw(import);

# Perl Nimbus
use Nimbus::API;
use Nimbus::PDS;

# Export utils functions
our @EXPORT_OK = qw(nimId generateAlarm generateQoS parseAlarmVariable generateDeviceId generateMetId ascii_oid isBase64);

sub rndStr {
    return join '', @_[ map { rand @_ } 1 .. shift ];
}

# Check if a given string is base64 or not
sub isBase64 {
    my ($str) = @_;
    return 0 if not defined $str;
    if($str =~ m/^([A-Za-z0-9+\/]{4})*([A-Za-z0-9+\/]{4}|[A-Za-z0-9+\/]{3}=|[A-Za-z0-9+\/]{2}==)$/) {
        return 1;
    }
    return 0;
}

# Generate NimSoft id
sub nimId {
    my $A = rndStr(10, 'A'..'Z', 0..9);
    my $B = rndStr(5, 0..9);
    return "$A-$B";
}

sub generateDeviceId {
    my $devId = rndStr(32, 'A'..'F', 0..9);
    return "D$devId";
}

sub generateMetricId {
    my $metId = rndStr(32, 'A'..'F', 0..9);
    return "M$metId";
}

sub parseAlarmVariable {
    my ($message, $hashRef) = @_;
    my $finalMsg    = $message;
    my $tMessage    = $message;
    my @matches     = ( $tMessage =~ /\$([A-Za-z0-9]+)/g );
    foreach (@matches) {
        next if not exists($hashRef->{"$_"});
        $finalMsg =~ s/\$\Q$_/$hashRef->{$_}/g;
    }
    return $finalMsg;
}

# Generate NimSoft alarm
sub generateAlarm {
    my ($subject, $hashRef) = @_;

    my $PDS = Nimbus::PDS->new(); 
    my $nimid = nimId();

    $PDS->string("nimid", $nimid);
    $PDS->number("nimts", time());
    $PDS->number("tz_offset", 0);
    $PDS->string("subject", $subject);
    $PDS->string("md5sum", "");
    $PDS->string("user_tag_1", $hashRef->{usertag1});
    $PDS->string("user_tag_2", $hashRef->{usertag2});
    $PDS->string("source", $hashRef->{source});
    $PDS->string("robot", $hashRef->{robot});
    $PDS->string("prid", $hashRef->{probe});
    $PDS->number("pri", $hashRef->{severity});
    $PDS->string("dev_id", $hashRef->{dev_id});
    $PDS->string("met_id", $hashRef->{met_id} || "");
    if (defined $hashRef->{supp_key}) { 
        $PDS->string("supp_key", $hashRef->{supp_key}) 
    };
    $PDS->string("suppression", $hashRef->{suppression});
    $PDS->string("origin", $hashRef->{origin});
    $PDS->string("domain", $hashRef->{domain});

    my $AlarmPDS = Nimbus::PDS->new(); 
    $AlarmPDS->number("level", $hashRef->{severity});
    $AlarmPDS->string("message", $hashRef->{message});
    $AlarmPDS->string("subsys", $hashRef->{subsystem} || "1.1.");
    if(defined $hashRef->{token}) {
        $AlarmPDS->string("token", $hashRef->{token});
    }

    $PDS->put("udata", $AlarmPDS, PDS_PDS);

    return ($PDS, $nimid);
}

# Generate NimSoft QoS PDS (And metricId if required).
sub generateQoS {
    my ($subject, $hashRef, $metricId) = @_;

    my $PDS = Nimbus::PDS->new(); 
    my $nimid = nimId();
    if(!defined($metricId)) {
        $metricId = generateMetricId();
    }

    $PDS->string("nimid",   $nimid);
    $PDS->number("nimts",   time());
    $PDS->string("subject", $subject);
    $PDS->string("md5sum",  "");
    $PDS->number("pri",     1);
    $PDS->string("source",  $hashRef->{source}) if defined($hashRef->{source});
    $PDS->string("robot",   $hashRef->{robot})  if defined($hashRef->{robot});
    $PDS->string("prid",    $hashRef->{probe})  if defined($hashRef->{probe});
    $PDS->string("origin",  $hashRef->{origin}) if defined($hashRef->{origin});
    $PDS->string("domain",  $hashRef->{domain}) if defined($hashRef->{domain});
    if($subject ne "QOS_DEFINITION") {
        $PDS->string("dev_id", $hashRef->{dev_id} || '');
        $PDS->string("met_id", $metricId);
    }

    my $udataPDS = Nimbus::PDS->new();
    if($subject eq "QOS_MESSAGE") {
        $udataPDS->string("qos", $hashRef->{udata}->{qos});
        $udataPDS->string("source", $hashRef->{udata}->{source});
        $udataPDS->string("target", $hashRef->{udata}->{target});
        $udataPDS->number("sampletime", $hashRef->{udata}->{sampletime});
        $udataPDS->number("sampletype", $hashRef->{udata}->{sampletype});
        $udataPDS->float("samplevalue", $hashRef->{udata}->{samplevalue});
        $udataPDS->float("samplestdev", $hashRef->{udata}->{samplestdev});
        $udataPDS->number("samplerate", $hashRef->{udata}->{samplerate});
    }
    elsif($subject eq "QOS_DEFINITION") {
        $udataPDS->string("name", $hashRef->{udata}->{name});
        $udataPDS->string("group", $hashRef->{udata}->{group});
        $udataPDS->string("description", $hashRef->{udata}->{description});
        $udataPDS->string("unit", $hashRef->{udata}->{unit});
        $udataPDS->string("unit_short", $hashRef->{udata}->{unit_short});
        $udataPDS->number("flags", $hashRef->{udata}->{flags});
        $udataPDS->number("type", $hashRef->{udata}->{type});
    }

    $PDS->put("udata", $udataPDS, PDS_PDS);

    return ($PDS, undef) if $subject eq "QOS_DEFINITION";
    return ($PDS, $metricId);
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

1;