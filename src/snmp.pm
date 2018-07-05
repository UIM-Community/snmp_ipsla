package src::snmp;

# Perl Core package(s)
use strict;

# SNMP Prototype Constructor
sub new {
    my ($class, $self) = @_;
    if(!defined($self->{SnmpProfileUUID}) || ref($self->{SnmpProfileUUID}) eq "HASH") {
        warn "Property 'SnmpProfileUUID' is missing (from XML File) for one of the SnmpProfile\n";
    }
    return bless($self, ref($class) || $class)
}

1;