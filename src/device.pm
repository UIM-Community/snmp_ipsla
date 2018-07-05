package src::device;

# Perl Core package(s)
use strict;

# Device Prototype Constructor
sub new {
    my ($class, $self) = @_;
    if(!defined($self->{PrimaryIPV4Address}) || $self->{PrimaryIPV4Address} eq "") {
        die "Property 'PrimaryIPV4Address' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(!defined($self->{SnmpProfileUUID}) || $self->{SnmpProfileUUID} eq "") {
        die "Property 'SnmpProfileUUID' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(!defined($self->{Label}) || $self->{Label} eq "") {
        die "Property 'Label' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    return bless($self, ref($class) || $class)
}

1;