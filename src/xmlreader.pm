package src::xmlreader;

# Perl Core package(s)
use strict;
use Data::Dumper;

# Third-party package(s)
use XML::Simple;

# Internal package(s)
use src::device;
use src::snmp;

# Nimsoft package(s)
use Nimbus::API;

# Parser filters!
our $filters;

sub new {
    my ($class, $filePath, $options) = @_;
    die "TypeError: filePath argument cant be undefined for constructor src::xmlreader->new(filepath)\n" if !defined($filePath);
    return bless({
        path => $filePath,
        options => $options || {},
        SnmpV1Profile => [],
        SnmpV2Profile => [],
        SnmpV3Profile => [],
        devices => []
    }, ref($class) || $class)
}

# PARSE The XML File!
sub parse {
    my ($self, $deviceRef) = @_;
    my $ref = XMLin($self->{path}, ForceArray => 0);
    my $DefaultOrigin = defined($ref->{DefaultOrigin}) ? $ref->{DefaultOrigin} : undef;
    my @localsFilters = @{ $filters };

    # Push devices (if exist).
    if(defined($ref->{Devices}) && defined($ref->{Devices}->{Device})) {
        my @devices = ();
        my @originDevices = ref($ref->{Devices}->{Device}) eq "HASH" ? ($ref->{Devices}->{Device}) : @{ $ref->{Devices}->{Device} };
        foreach(@originDevices) {
            if(!defined($_->{Origin}) && defined($DefaultOrigin)) {
                $_->{Origin} = $DefaultOrigin;
            }
            eval {
                # Only if we match Vendor and Model field requirement!
                print Dumper($_);
                print "\n";
                my $dev = src::device->new($_);
                print STDOUT "Handle XML Device with Label => $dev->{Label}\n";
                nimLog(3, "Handle XML Device with Label => $dev->{Label}");
                filterW: foreach my $filterRef (@localsFilters) {
                    filterK: foreach my $filterKey (keys %{ $filterRef }) {
                        next filterK if !defined($dev->{$filterKey});
                        next filterK unless($dev->{$filterKey} =~ $filterRef->{$filterKey});
                        if(defined($deviceRef->{$dev->{Label}})) {
                            print STDOUT "Device with Label $dev->{Label} is not active anymore\n";
                            nimLog(3, "Device with Label $dev->{Label} is not active anymore");
                        }
                        else {
                            print STDOUT "Device $dev->{Label} is matching filtering rules...\n";
                            nimLog(3, "Device $dev->{Label} is matching filtering rules...");
                            push(@devices, $dev);
                        }
                        last filterW;
                    }
                }
            };
            nimLog(2, $@) if $@;
            print STDERR $@ if $@;
        };
        $self->{devices} = \@devices;
    }

    # Push SnmpProfile(s) XML Section (if they exist).
    my @poll = ('SnmpV1Profile', 'SnmpV2Profile', 'SnmpV3Profile');
    foreach my $name (@poll) {
        my $longName = "${name}s";
        next if !defined($ref->{$longName});
        next if !defined($ref->{$longName}->{$name});
        my @snmp = ();
        my @originSNMP = ref($ref->{$longName}->{$name}) eq "HASH" ? ($ref->{$longName}->{$name}) : @{ $ref->{$longName}->{$name} };
        foreach(@originSNMP) {
            eval {
                push(@snmp, src::snmp->new($_));
            };
            nimLog(2, $@) if $@;
            print STDERR $@ if $@;
        };
        $self->{$name} = \@snmp;
    }

    return $self;
}

# Get devices array (values)
sub devicesList {
    my ($self) = @_;
    return @{ $self->{devices} };
}

# Get snmp (v1, v2, v3) array (values) contained in a hashref
sub snmpList {
    my ($self) = @_;
    return {
        v1 => $self->{SnmpV1Profile},
        v2 => $self->{SnmpV2Profile},
        v3 => $self->{SnmpV3Profile}
    };
}

# Delete XML File !
sub deleteFile {
    my ($self) = @_;
    unlink($self->{path}) or die "Error: Unable to unlink (delete) file $self->{path}\n";
}

1;