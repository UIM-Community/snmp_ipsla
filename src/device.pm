package src::device;

# Perl Core package(s)
use strict;

# Check if an XML field is defined or not
sub isNotDefined {
    return !defined @_[0] || ref @_[0] eq "HASH" || @_[0] eq "" ? 1 : 0;
}

# Device Prototype Constructor
sub new {
    my ($class, $self) = @_;
    if(isNotDefined($self->{PrimaryIPV4Address})) {
        warn "Property 'PrimaryIPV4Address' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(isNotDefined($self->{SnmpProfileUUID})) {
        warn "Property 'SnmpProfileUUID' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }
    if(isNotDefined($self->{Label})) {
        warn "Property 'Label' is missing (from XML File) for device with UUID <$self->{ElementUUID}>\n";
    }

    return bless($self, ref($class) || $class)
}

1;