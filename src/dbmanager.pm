package src::dbmanager;

# Perl Core package(s)
use strict;
use Thread::Queue;
use Data::Dumper;

# Third-party package(s)
use DBI;

# use Internal package(s)
use src::utils;

# HashMap of SNMP records
my %SNMP_VMatch = (
    v1 => 'nokia_ipsla_snmp_v1',
    v2 => 'nokia_ipsla_snmp_v2',
    v3 => 'nokia_ipsla_snmp_v3'
);

# Static module variable
our $encryption = 0;

# DBManager Prototype Constructor
sub new {
    my ($class, $dbName, $dbKey) = @_;
    my $DB = DBI->connect("dbi:SQLcipher:uri=file:${dbName}?mode=rwc", "", "", {
        RaiseError => 1
    });
    $DB->do("pragma key =\"$dbKey\";") if $encryption == 1;
    return bless({
        DB => $DB
    }, ref($class) || $class);
}

# Upsert XML Object
sub upsertXMLObject {
    my ($self, $XML) = @_;
    die "Error: XML (Ref Argument) is not a instance of src::xmlreader" if (ref($XML) || $XML) ne "src::xmlreader";
    
    # Split and Handle DeviceElements
    my @devices = $XML->devicesList();
    my @devicesToCreate = ();

    while (defined(my $device = shift @devices)){
        my ($rowCount) = $self->{DB}->selectrow_array("SELECT count(*) FROM nokia_ipsla_device WHERE uuid = \"$device->{ElementUUID}\"");
        push(@devicesToCreate, $device) if $rowCount == 0;
    }
    undef @devices;

    # Create all Devices in the SQLite db
    if(scalar(@devicesToCreate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $device = shift @devicesToCreate)) {
            my $devId = src::utils::generateDeviceId();
            $self->{DB}->prepare('INSERT INTO nokia_ipsla_device (uuid, snmp_uuid, name, ip, dev_id) VALUES (?, ?, ?, ?, ?)')->execute(
                $device->{ElementUUID},
                $device->{SnmpProfileUUID},
                $device->{Label},
                $device->{PrimaryIPV4Address},
                $devId
            );
        }
        $self->{DB}->commit;
    }
    undef @devicesToCreate;

    # Split and Handler SNMPEquipements
    my $SNMP_VHash = $XML->snmpList();
    my @snmpV1ToCreate = ();
    my @snmpV1ToUpdate = ();

    my @snmpV2ToCreate = ();
    my @snmpV2ToUpdate = ();

    my @snmpV3ToCreate = ();
    my @snmpV3ToUpdate = (); 

    foreach my $snmpVersion (keys %{$SNMP_VHash}) {
        my @snmpSecrets = @{ $SNMP_VHash->{$snmpVersion} };
        next if scalar(@snmpSecrets) == 0;

        my $tableName = $SNMP_VMatch{$snmpVersion};
        foreach my $snmp (@snmpSecrets) {
            my ($rowCount) = $self->{DB}->selectrow_array("SELECT count(*) FROM $tableName WHERE uuid = \"$snmp->{SnmpProfileUUID}\"");
            if($rowCount == 0) {
                push(@snmpV3ToCreate, $snmp) if $tableName eq "nokia_ipsla_snmp_v3";
                push(@snmpV1ToCreate, $snmp) if $tableName eq "nokia_ipsla_snmp_v1";
                push(@snmpV2ToCreate, $snmp) if $tableName eq "nokia_ipsla_snmp_v2";
            }
            elsif($rowCount == 1) {
                push(@snmpV3ToUpdate, $snmp) if $tableName eq "nokia_ipsla_snmp_v3";
                push(@snmpV1ToUpdate, $snmp) if $tableName eq "nokia_ipsla_snmp_v1";
                push(@snmpV2ToUpdate, $snmp) if $tableName eq "nokia_ipsla_snmp_v2";
            }
        }
    }
    undef $SNMP_VHash;

    # Create SNMPV3 Equipments in the SQLite db
    if(scalar(@snmpV3ToCreate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $snmp = shift @snmpV3ToCreate)) {
            my $Query = 'INSERT INTO nokia_ipsla_snmp_v3 (uuid, description, username, auth_protocol, auth_key, priv_protocol, priv_key, port) VALUES (?, ?, ?, ?, ?, ?, ?, ?)';
            $self->{DB}->prepare($Query)->execute(
                $snmp->{SnmpProfileUUID},
                $snmp->{Description},
                $snmp->{UserName},
                $snmp->{AuthenticationProtocol},
                $snmp->{AuthenticationKey},
                $snmp->{PrivacyProtocol},
                $snmp->{PrivacyKey},
                $snmp->{Port}
            );
        }
        $self->{DB}->commit;
    }
    undef @snmpV3ToCreate;

    # Create SNMP V1 Or V2 Equipments in the SQLite db
    if(scalar(@snmpV1ToCreate) > 0 || scalar(@snmpV2ToCreate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $snmp = shift @snmpV1ToCreate)) {
            $self->{DB}->prepare('INSERT INTO nokia_ipsla_snmp_v1 (uuid, description, community, port) VALUES (?, ?, ?, ?)')->execute(
                $snmp->{SnmpProfileUUID},
                $snmp->{Description},
                $snmp->{Community},
                $snmp->{Port}
            );
        }
        while (defined(my $snmp = shift @snmpV2ToCreate)) {
            $self->{DB}->prepare('INSERT INTO nokia_ipsla_snmp_v2 (uuid, description, community, port) VALUES (?, ?, ?, ?)')->execute(
                $snmp->{SnmpProfileUUID},
                $snmp->{Description},
                $snmp->{Community},
                $snmp->{Port}
            );
        }
        $self->{DB}->commit;
    }
    undef @snmpV1ToCreate;
    undef @snmpV2ToCreate;

    # Update SNMPV3 Equipments in the SQLite db
    if(scalar(@snmpV3ToUpdate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $snmp = shift @snmpV3ToUpdate)) {
            my $Query = 'UPDATE nokia_ipsla_snmp_v3 SET description=?, username=?, auth_protocol=?, auth_key=?, priv_protocol=?, priv_key=?, port=? WHERE uuid=?';
            $self->{DB}->prepare($Query)->execute(
                $snmp->{Description},
                $snmp->{UserName},
                $snmp->{AuthenticationProtocol},
                $snmp->{AuthenticationKey},
                $snmp->{PrivacyProtocol},
                $snmp->{PrivacyKey},
                $snmp->{Port},
                $snmp->{SnmpProfileUUID}
            );
        }
        $self->{DB}->commit;
    }
    undef @snmpV3ToUpdate;

    # Update SNMP V1 Or V2 Equipments in the SQLite db
    if(scalar(@snmpV1ToUpdate) > 0 || scalar(@snmpV2ToUpdate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $snmp = shift @snmpV1ToUpdate)) {
            $self->{DB}->prepare('UPDATE nokia_ipsla_snmp_v1 SET description=?, community=?, port=? WHERE uuid=?')->execute(
                $snmp->{Description},
                $snmp->{Community},
                $snmp->{Port},
                $snmp->{SnmpProfileUUID},
            );
        }
        while (defined(my $snmp = shift @snmpV2ToUpdate)) {
            $self->{DB}->prepare('UPDATE nokia_ipsla_snmp_v2 SET description=?, community=?, port=? WHERE uuid=?')->execute(
                $snmp->{Description},
                $snmp->{Community},
                $snmp->{Port},
                $snmp->{SnmpProfileUUID}
            );
        }
        $self->{DB}->commit;
    }
    undef @snmpV1ToUpdate;
    undef @snmpV2ToUpdate;

    return $self;
}

# checkAttributes attr
sub checkAttributes {
    my ($self, $hashRef, $device) = @_;

    my @toCreate = ();
    my @toUpdate = ();
    my %Hash = %{ $hashRef };
    foreach my $key (keys %Hash) {
        my $value = $Hash{$key};
        my ($rowCount) = $self->{DB}->selectrow_array("SELECT count(*) FROM nokia_ipsla_device_attr WHERE dev_uuid = \"$device->{dev_uuid}\" AND key = \"$key\"");
        my $payload = {
            key => $key,
            value => $value
        };
        push(@toCreate, $payload) if $rowCount == 0;
        push(@toUpdate, $payload) if $rowCount == 1;
    }

    if(scalar(@toCreate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $attr = shift @toCreate)) {
            $self->{DB}->prepare('INSERT INTO nokia_ipsla_device_attr (dev_uuid, key, value) VALUES (?, ?, ?)')->execute(
                $device->{dev_uuid},
                $attr->{key},
                $attr->{value}
            );
        }
        $self->{DB}->commit;
    }

    if(scalar(@toUpdate) > 0) {
        $self->{DB}->begin_work;
        while (defined(my $attr = shift @toUpdate)) {
            $self->{DB}->prepare('UPDATE nokia_ipsla_device_attr SET value=? WHERE key=? AND dev_uuid=?')->execute(
                $attr->{value},
                $attr->{key},
                $device->{dev_uuid}
            );
        }
        $self->{DB}->commit;
    }
}

# update pollable
sub updatePollable {
    my ($self, $uuid, $pollable) = @_;
    $self->{DB}->prepare('UPDATE nokia_ipsla_device SET is_pollable=? WHERE uuid=?')->execute(
        $pollable,
        $uuid
    );
}

# Get pollable devices!
sub pollable_devices {
    my ($self) = @_; 
    my $sth = $self->{DB}->prepare('SELECT * FROM v_pollable_devices');
    $sth->execute();
    my @rows = ();
    while(my $row = $sth->fetchrow_hashref) {
        push(@rows, $row);
    }
    return \@rows;
}

# Get unpollable devices!
sub unpollable_devices {
    my ($self) = @_; 
    my $sth = $self->{DB}->prepare('SELECT * FROM v_unpollable_devices');
    $sth->execute();
    my @rows = ();
    while(my $row = $sth->fetchrow_hashref) {
        push(@rows, $row);
    }
    return \@rows;
}

# Import SQLite database table definition!
sub import_def {
    my ($self, $filePath) = @_;
    open(my $list, '<:encoding(UTF-8)', $filePath) or die "Error: failed to import SQL (Definition) File!\n";
    my $SQLQuery = '';
    while(my $row = <$list>) {
        $row =~ s/^\s+|\s+$//g;
        $SQLQuery .= $row;
    }
    $self->{DB}->{sqlite_allow_multiple_statements} = 1;
    $self->{DB}->do("$SQLQuery");
    $self->{DB}->do("CREATE VIEW IF NOT EXISTS v_pollable_devices
    AS 
    SELECT DEV1.name, DEV1.ip, DEV1.uuid as dev_uuid, '1' AS snmp_version, V1.uuid, DEV1.dev_id, V1.port, V1.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v1 AS V1
    JOIN nokia_ipsla_device AS DEV1 ON DEV1.snmp_uuid = V1.uuid WHERE DEV1.is_pollable=1 AND DEV1.is_active=1
    UNION
    SELECT DEV2.name, DEV2.ip, DEV2.uuid as dev_uuid, '2' AS snmp_version, V2.uuid, DEV2.dev_id, V2.port, V2.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v2 AS V2
    JOIN nokia_ipsla_device AS DEV2 ON DEV2.snmp_uuid = V2.uuid WHERE DEV2.is_pollable=1 AND DEV2.is_active=1
    UNION
    SELECT DEV3.name, DEV3.ip, DEV3.uuid as dev_uuid, '3' AS snmp_version, V3.uuid, DEV3.dev_id, V3.port, '' AS community, V3.username, V3.auth_protocol, V3.auth_key, V3.priv_protocol, V3.priv_key FROM nokia_ipsla_snmp_v3 AS V3
    JOIN nokia_ipsla_device AS DEV3 ON DEV3.snmp_uuid = V3.uuid WHERE DEV3.is_pollable=1 AND DEV3.is_active=1");
    $self->{DB}->do("CREATE VIEW IF NOT EXISTS v_unpollable_devices
    AS 
    SELECT DEV1.name, DEV1.ip, DEV1.uuid as dev_uuid, '1' AS snmp_version, V1.uuid, DEV1.dev_id, V1.port, V1.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v1 AS V1
    JOIN nokia_ipsla_device AS DEV1 ON DEV1.snmp_uuid = V1.uuid WHERE DEV1.is_pollable=0 AND DEV1.is_active=1 
    UNION
    SELECT DEV2.name, DEV2.ip, DEV2.uuid as dev_uuid, '2' AS snmp_version, V2.uuid, DEV2.dev_id, V2.port, V2.community, '' AS username, '' AS auth_protocol, '' AS auth_key, '' AS priv_protocol, '' AS priv_key FROM nokia_ipsla_snmp_v2 AS V2
    JOIN nokia_ipsla_device AS DEV2 ON DEV2.snmp_uuid = V2.uuid WHERE DEV2.is_pollable=0 AND DEV2.is_active=1
    UNION
    SELECT DEV3.name, DEV3.ip, DEV3.uuid as dev_uuid, '3' AS snmp_version, V3.uuid, DEV3.dev_id, V3.port, '' AS community, V3.username, V3.auth_protocol, V3.auth_key, V3.priv_protocol, V3.priv_key FROM nokia_ipsla_snmp_v3 AS V3
    JOIN nokia_ipsla_device AS DEV3 ON DEV3.snmp_uuid = V3.uuid WHERE DEV3.is_pollable=0 AND DEV3.is_active=1");
    $self->{DB}->{sqlite_allow_multiple_statements} = 0;
    return $self;
}

sub close {
    my ($self) = @_;
}

1;