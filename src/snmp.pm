package src::snmp;

# Perl Core package(s)
use strict;

# Check if an XML field is defined or not
sub isNotDefined {
    return !defined @_[0] || ref @_[0] eq "HASH" || @_[0] eq "" ? 1 : 0;
}

# SNMP Prototype Constructor
sub new {
    my ($class, $self) = @_;
    if(isNotDefined($self->{SnmpProfileUUID})) {
        warn "Property 'SnmpProfileUUID' is missing (from XML File) for one of the SnmpProfile\n";
    }
    return bless($self, ref($class) || $class)
}

1;