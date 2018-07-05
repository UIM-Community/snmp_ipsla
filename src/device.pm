package src::device;

# Perl Core package(s)
use strict;

# Device Prototype Constructor
sub new {
    my ($class, $self) = @_;
    my $ref = ref($self->{PrimaryIPV4Address});
    if(!defined($self->{PrimaryIPV4Address}) || ref($self->{PrimaryIPV4Address}) eq "HASH") {
        warn "Property 'PrimaryIPV4Address' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(!defined($self->{SnmpProfileUUID}) || ref($self->{SnmpProfileUUID}) eq "HASH") {
        warn "Property 'SnmpProfileUUID' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(!defined($self->{Label}) || ref($self->{Label}) eq "HASH") {
        warn "Property 'Label' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    return bless($self, ref($class) || $class)
}

1;