package src::filemap;

# Perl Core package(s)
use strict;

# Perl Nimbus
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::CFG;

sub strBeginWith {
    return substr($_[0], 0, length($_[1])) eq $_[1];
}

sub new {
    my ($class,$location) = @_;
    my %Hash = ();
    my $this = {
        location => $location,
        sections => \%Hash
    };
    if(index($location,'.cfg') == -1) {
        die "Invalid manifest file $location";
    }
    if(not -f $location) {
        open my $fh, '>', "$location";
        close $fh;
    }
    $this->{file} = cfgOpen($location,0);
    my ($list) = cfgSectionList($this->{file});
    foreach(@$list) {
        $this->{sections}->{$_} = 1;
    }
    my $blessed = bless($this,ref($class) || $class);
    return $blessed;
}

sub begins_with {
    return substr($_[0], 0, length($_[1])) eq $_[1];
}

sub has {
    my ($self,$key) = @_;
    if(not strBeginWith($key,'/')) {
        $key = "/$key";
    }
    if(defined $self->{sections}->{$key}) {
        return 1;
    }
    return 0;
}

sub getParams {
    my ($self,$key) = @_;
    if(not strBeginWith($key,'/')) {
        $key = "/$key";
    }
    my ($list) = cfgKeyList($self->{file},$key);
    my %HashRef = ();
    foreach(@$list) {
        $HashRef{$_} = cfgKeyRead($self->{file},$key,$_);
    }
    return \%HashRef;
}

sub set {
    my ($self, $key, $hashRefParams) = @_;
    if(not strBeginWith($key,'/')) {
        $key = "/$key";
    }
    if($self->has($key)) {
        if(defined $hashRefParams) {
            foreach(keys %{ $hashRefParams }) {
                cfgKeyDelete($self->{file}, $key, $_);
                cfgKeyWrite($self->{file}, $key, $_, $hashRefParams->{$_});
            }
        }
    }
    else {
        cfgKeyWrite($self->{file},$key,$key,'');
        cfgKeyDelete($self->{file},$key,$key);
        if(defined $hashRefParams) {
            cfgKeyWrite($self->{file}, $key, $_, $hashRefParams->{$_}) for keys %{ $hashRefParams };
        }
    }
    return $self;
}

sub delete {
    my ($self,$key) = @_;
    if(not strBeginWith($key,'/')) {
        $key = "/$key";
    }
    cfgSectionDelete($self->{file},$key);
    return $self;
}

sub writeToDisk {
    my ($self) = @_;
    cfgSync($self->{file});
    return $self;
}

1;
