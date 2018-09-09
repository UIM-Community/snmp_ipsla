package src::xmlreader;

# Perl Core package(s)
use strict;
use warnings;
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

# Check if an XML field is defined or not
sub isNotDefined {
    return !defined @_[0] || ref @_[0] eq "HASH" || @_[0] eq "" ? 1 : 0;
}

# XMLReader prototype constructor
sub new {
    my ($class, $filePath, $options) = @_;
    if (!defined $filePath) {
        warn "TypeError: filePath argument can't be undefined for constructor src::xmlreader->new(filepath)\n";
    }

    return bless({
        path => $filePath,
        options => $options || {},
        SnmpV1Profile => [],
        SnmpV2Profile => [],
        SnmpV3Profile => [],
        devices => []
    }, ref($class) || $class)
}

# @memberof xmlreader
# @routine parse
# @desc Open, Read and parse the XML file
sub parse {
    my ($self, $deviceRef) = @_;

    # Open XMLin handle
    my $ref = XMLin($self->{path}, ForceArray => 0);
    my $DefaultOrigin = defined($ref->{DefaultOrigin}) ? $ref->{DefaultOrigin} : undef;
    my @localsFilters = @{ $filters };

    # Push devices (if exist).
    if(defined($ref->{Devices}) && defined($ref->{Devices}->{Device})) {
        my @devices = ();
        my @originDevices = ref($ref->{Devices}->{Device}) eq "HASH" ? ($ref->{Devices}->{Device}) : @{ $ref->{Devices}->{Device} };

        foreach(@originDevices) {
            # Setup DefaultOrigin is not Origin field defined
            if(!defined($_->{Origin}) && defined($DefaultOrigin)) {
                $_->{Origin} = $DefaultOrigin;
            }

            # Create the device
            my $dev = src::device->new($_);
            next if isNotDefined($dev->{PrimaryIPV4Address});
            next if isNotDefined($dev->{SnmpProfileUUID});
            next if isNotDefined($dev->{Label});
            print STDOUT "Handle XML Device with Label => $dev->{Label}\n";
            nimLog(3, "Handle XML Device with Label => $dev->{Label}");

            # Check if we match all filters before pushing $dev in @devices
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

        # Apply retrived devices
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
            my $snmp = src::snmp->new($_);
            push(@snmp, $snmp) if not isNotDefined($snmp->{SnmpProfileUUID});
        };

        # Apply retrived SNMP Profiles
        $self->{$name} = \@snmp;
    }

    return $self;
}

# @memberof xmlreader
# @routine devicesList
# @desc Return the complete devices list as an Array
sub devicesList {
    my ($self) = @_;

    return @{ $self->{devices} };
}

# @memberof xmlreader
# @routine snmpList
# @desc Get snmp (v1, v2, v3) array (values) contained in a hashref
sub snmpList {
    my ($self) = @_;

    return {
        v1 => $self->{SnmpV1Profile},
        v2 => $self->{SnmpV2Profile},
        v3 => $self->{SnmpV3Profile}
    };
}

# @memberof xmlreader
# @routine deleteFile
# @desc Delete the XML File linked with this XML Instance
sub deleteFile {
    my ($self) = @_;

    unlink($self->{path}) or die "Error: Unable to unlink (delete) file $self->{path}\n";
}

1;