# Perl prototype created to load all Devices from cm_data_import XML File like
# https://docops.ca.com/ca-unified-infrastructure-management/8-4/en/installing-ca-uim/discover-systems-to-monitor/configuring-discovery/run-file-based-import/xml-file-schema/

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

    # Throw a warning if one of the following fields is missing !
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