package src::utils;

# Perl Core package(s)
use strict;
use Exporter qw(import);

# Perl Nimbus
use Nimbus::API;
use Nimbus::PDS;

# Export utils functions
our @EXPORT_OK = qw(nimId generateAlarm parseAlarmVariable generateDeviceId generateMetId);

sub rndStr {
    return join '', @_[ map { rand @_ } 1 .. shift ];
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

1;