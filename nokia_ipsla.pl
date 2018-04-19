use lib "/opt/nimsoft/perllib";
use lib "/opt/nimsoft/perl/lib";

# Set env variable NIM_ROOT
$ENV{'NIM_ROOT'} = '/opt/nimsoft';

# Use Perl core Package(s)
use strict;
use POSIX;
use threads;
use Thread::Queue;
use threads::shared;
use Data::Dumper;
use Time::Piece;

# Use Third-party Package(s)
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::Session;
use Nimbus::CFG;
use DBI;

# Use internals Package(s)
use src::xmlreader;
use src::dbmanager;
use src::snmpmanager;
use src::utils;

# Declare Script CONSTANT(S) and Global(s)
use constant {
    PROBE_NAME => "nokia_ipsla",
    CFG_FILE => "nokia_ipsla.cfg",
    VERSION => "1.3"
};
my $XMLDirectory: shared;
my ($ProvisioningInterval, $T_CheckInterval, $T_HealthInterval, $HealthThreads, $ProvisioningOnStart, $T_PollingInterval);
my ($RemoveDevicesInterval, $T_RemoveDevicesInterval, $DecommissionSQLTable);
my ($DB_ConnectionString, $DB_User, $DB_Password);
my $CRED_KEY = "secret_key";
my $PollingInterval: shared;
my $HealthInterval: shared;
my $BOOL_DeleteXML: shared = 1;
my $readXML_open: shared = 0;
my $updateDevicesAttr: shared = 0;
my $alarmThreadRunning: shared = 0;
my $removeDevicesRunning: shared = 0;
my $sess;

# SNMP QoS Parser routines
my $SnmpQoSValueParser = {
    us => sub {
        my ($strValue) = @_;
        my @matches = $strValue =~ /(.*)\smicroseconds/g;
        return $matches[0];
    },
    State => sub {
        my ($strValue) = @_;
        return $strValue eq "success";
    }
};

# SNMP QoS Schema
my $SnmpQoSSchema = {
    tmnxOamPingResultsMinRtt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsAverageRtt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsMaxTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsInTtSumOfSqrs => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsInJitter => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsTtOFSumSquares => '0',
    tmnxOamPingResultsAverageTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsOutJitter => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsMaxRtt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsMaxInTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsRttOFSumSquares => '0',
    tmnxOamPingResultsMinTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsTestRunResult => {
        unit => "State",
        short => "",
        group => "QOS_NETWORK",
        description => "",
        flags => 1
    },
    tmnxOamPingResultsInTtHCSumSqrs => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsSvcPing => 'undetermined',
    #tmnxOamPingResultsSentProbes => '1 probes',
    tmnxOamPingResultsRttSumOfSquares => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsOperStatus => 'disabled',
    tmnxOamPingResultsTtSumOfSquares => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsInTtOFSumSqrs => '0',
    #tmnxOamPingResultsProbeResponses => '1 responses',
    #tmnxOamPingResultsLastGoodProbe => '2018-3-27,14:39:0.0,+0:0',
    #tmnxOamPingResultsMtuResponseSize => '0 Octets',
    #tmnxOamPingResultsProbeTimeouts => '0',
    tmnxOamPingResultsAverageInTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsRtJitter => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsRttHCSumSquares => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    tmnxOamPingResultsMinInTt => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    },
    #tmnxOamPingResultsOutOfOrder => '0 reply PDUs',
    #tmnxOamPingResultsProbeFailures => '0',
    tmnxOamPingResultsTtHCSumSquares => {
        unit => "us",
        short => "us",
        group => "QOS_NETWORK",
        description => "",
        flags => 0
    }
};

# Queues
my $AlarmQueue = Thread::Queue->new();
my $deviceHandlerQueue = Thread::Queue->new();
my $QoSHandlers = Thread::Queue->new();

# Unexcepted Script die!
$SIG{__DIE__} = \&scriptDieHandler;

# @subroutine scriptDieHandler
# @desc Routine triggered when the script die
sub scriptDieHandler {
    my ($err) = @_;
    print STDERR "$err\n";
    nimLog(0, "$err");
    exit(1);
}

# @subroutine getMySQLConnector
# @desc get MySQLConnector
sub getMySQLConnector {
    nimLog(3, "Initialize MySQL connection: (CS: $DB_ConnectionString)");
    my $dbh = DBI->connect($DB_ConnectionString, $DB_User, $DB_Password);
    if(!defined($dbh)) {
        nimLog(1, "Failed to connect to the MySQL Database...");
    }
    return $dbh;
}

# @subroutine processProbeConfiguration
# @desc Read and apply default probe Configuration !
sub processProbeConfiguration {
    my $processProbeConfigurationTime = nimTimerCreate();
    nimTimerStart($processProbeConfigurationTime);
    my $CFG                 = Nimbus::CFG->new(CFG_FILE);

    # Setup section
    my $STR_Login           = $CFG->{"setup"}->{"nim_login"} || "administrator";
    my $STR_Password        = $CFG->{"setup"}->{"nim_password"};
    my $INT_LogLevel        = defined($CFG->{"setup"}->{"loglevel"}) ? $CFG->{"setup"}->{"loglevel"} : 5;
    my $INT_LogSize         = $CFG->{"setup"}->{"logsize"} || 1024;
    my $STR_LogFile         = $CFG->{"setup"}->{"logfile"} || "nokia_ipsla.log";
    scriptDieHandler("Configuration <provisioning> section is not mandatory!") if not defined($CFG->{"provisioning"});

    # Database Section
    my $DBName      = $CFG->{"database"}->{"database"} || "ca_uim";
    my $DBHost      = $CFG->{"database"}->{"host"};
    my $DBPort      = $CFG->{"database"}->{"port"};
    $DB_ConnectionString = "DBI:mysql:database=$DBName;host=$DBHost;port=$DBPort";
    $DB_User        = $CFG->{"database"}->{"user"};
    $DB_Password    = $CFG->{"database"}->{"password"};

    # Crypt CFG Credential keys!
    if(substr($DB_Password, length($DB_Password) - 2, 2) ne "==") {
        my $CFGNapi = cfgOpen(CFG_FILE, 0);
        my $cValue = nimEncryptString($CRED_KEY, $DB_Password);
        cfgKeyWrite($CFGNapi, "/database/", "password", $cValue); 
        cfgSync($CFGNapi);
        cfgClose($CFGNapi);
    }
    else {
        $DB_Password = nimDecryptString($CRED_KEY, $DB_Password);
    }

    # provisioning Section 
    $XMLDirectory           = $CFG->{"provisioning"}->{"xml_dir"} || "./xml";
    $RemoveDevicesInterval  = $CFG->{"provisioning"}->{"decommission_interval"} || 300;
    $DecommissionSQLTable   = $CFG->{"provisioning"}->{"decommission_sqltable"} || "nokia_ipsla_decommission";
    $ProvisioningInterval   = $CFG->{"provisioning"}->{"provisioning_interval"} || 30;
    $PollingInterval        = $CFG->{"provisioning"}->{"polling_snmp_interval"} || 360;
    $HealthInterval         = $CFG->{"provisioning"}->{"polling_health_interval"} || 30;
    $HealthThreads          = $CFG->{"provisioning"}->{"polling_health_threads"} || 3;
    $ProvisioningOnStart    = defined($CFG->{"provisioning"}->{"provisioning_on_start"}) ? $CFG->{"provisioning"}->{"provisioning_on_start"} : 0;
    $BOOL_DeleteXML         = defined($CFG->{"provisioning"}->{"delete_xml_files"}) ? $CFG->{"provisioning"}->{"delete_xml_files"} : 1;

    my @filters = ();
    if(defined($CFG->{"provisioning"}->{"xml_device_filters"})) {
        foreach my $index (keys $CFG->{"provisioning"}->{"xml_device_filters"}) {
            my $hash = $CFG->{"provisioning"}->{"xml_device_filters"}->{$index};
            foreach my $filterKey (keys $hash) {
                $hash->{$filterKey} = qr/$hash->{$filterKey}/;
            }
            push(@filters, $hash);
        }
    }
    $src::xmlreader::filters = \@filters;

    # Check XML Directory
    mkdir($XMLDirectory) if -d $XMLDirectory;

    # Login to Nimsoft if required
    nimLogin("$STR_Login","$STR_Password") if defined($STR_Login) && defined($STR_Password);

    # Configure Nimsoft Log!
    nimLogSet($STR_LogFile, '', $INT_LogLevel, NIM_LOGF_NOTRUNC);
    nimLogTruncateSize($INT_LogSize * 1024);
    nimLog(3, "Probe Nokia_ipsla started!"); 

    # Minmum security threshold for PollingInterval
    if($PollingInterval < 60 || $PollingInterval > 1800) {
        print STDOUT "SNMP Polling interval minimum and threshold is <60/1800> seconds!\n";
        nimLog(2, "SNMP Polling interval minimum and threshold is <60/1800> seconds!"); 
        $PollingInterval = 60;
    }

    # Minimum security threshold for CheckInterval
    if($ProvisioningInterval < 10) {
        print STDOUT "Provisioning interval threshold is 10 seconds!\n";
        nimLog(2, "Provisioning interval threshold is 10 seconds!"); 
        $ProvisioningInterval = 10;
    }

    # Nimsoft timer (init /or/ re-init).
    $T_CheckInterval            = nimTimerCreate();
    $T_HealthInterval           = nimTimerCreate();
    $T_PollingInterval          = nimTimerCreate();
    $T_RemoveDevicesInterval    = nimTimerCreate();
    nimTimerStart($T_CheckInterval);
    nimTimerStart($T_HealthInterval);
    nimTimerStart($T_PollingInterval);
    nimTimerStart($T_RemoveDevicesInterval);

    nimQoSSendDefinition(
        "QOS_REACHABILITY",
        "QOS_NETWORK",
        "Network connectivity response",
        "State",
        "",
        NIMQOS_DEF_BOOLEAN
    );
    foreach my $QoSName (keys %{ $SnmpQoSSchema }) {
        my $QoS = $SnmpQoSSchema->{$QoSName};
        print STDOUT "Send QoSDefinition QOS_$QoSName\n";
        nimLog(3, "Send QoSDefinition QOS_$QoSName");
        nimQoSSendDefinition(
            "QOS_$QoSName",
            $QoS->{group},
            $QoS->{group},
            $QoS->{unit},
            $QoS->{short},
            $QoS->{flags}
        );
    }

    nimTimerStop($processProbeConfigurationTime);
    my $executionTimeMs = nimTimerDiff($processProbeConfigurationTime);
    nimTimerFree($processProbeConfigurationTime);
    print STDOUT "processProbeConfiguration() has been executed in ${executionTimeMs}ms\n";
    nimLog(3, "processProbeConfiguration() has been executed in ${executionTimeMs}ms");

    if($ProvisioningOnStart == 1) {
        print STDOUT "Provisioning on start activated: Triggering updateInterval() method!\n";
        nimLog(3, "Provisioning on start activated: Triggering updateInterval() method!");
        updateInterval();
    }
}

# @subroutine alarmsThread
# @desc Thread that handle all alarms
sub alarmsThread {
    $alarmThreadRunning = 1;
    print STDOUT "Run a new thread for alarming!\n";
    nimLog(3, "Run a new thread for alarming!");

    # Open and Read CFG File
    my $CFG     = Nimbus::CFG->new(CFG_FILE);
    my $Alarm   = defined($CFG->{"messages"}) ? $CFG->{"messages"} : {};

    # Request local (agent/robot) informations
    # Retrieve robot informations!
    my ($RC, $getInfoPDS) = nimNamedRequest("controller", "get_info", Nimbus::PDS->new);
    scriptDieHandler(
        "Failed to establish a communication with the local controller probe!"
    ) if $RC != NIME_OK;
    my $localAgent      = Nimbus::PDS->new($getInfoPDS)->asHash();
    my $defaultOrigin   = defined($Alarm->{default_origin}) ? $Alarm->{default_origin} : $localAgent->{origin};

    # Unqueue alarm message!
    while ( defined ( my $hAlarm = $AlarmQueue->dequeue() ) )  {
        # Verify Alarm Type
        next if not defined($hAlarm->{type});
        next if not defined($Alarm->{$hAlarm->{type}});
        print "Receiving new alarm of type: $hAlarm->{type}\n";
        nimLog(3, "Receiving new alarm of type: $hAlarm->{type}");
        my $type = $Alarm->{$hAlarm->{type}};

        # Parse and Define alarms variables
        my $hVariablesRef = defined($hAlarm->{payload}) ? $hAlarm->{payload} : {};
        $hVariablesRef->{host} = $hAlarm->{device};
        my $suppkey = src::utils::parseAlarmVariable($type->{supp_key}, $hVariablesRef);
        my $message = src::utils::parseAlarmVariable($type->{message}, $hVariablesRef);
        undef $hVariablesRef;

        if(defined($hAlarm->{hCI})) {
            my $hCI = $hAlarm->{hCI};
            my ($RC, $nimid) = ciAlarm(
                $hCI,
                $hAlarm->{metric},
                $type->{severity},
                $message,
                "",
                Nimbus::PDS->new()->data,
                $type->{subsys},
                $suppkey,
                $hAlarm->{source}
            );
            print STDOUT "Generate new (CI) alarm with id $nimid\n";
            nimLog(3, "Generate new (CI) alarm with id $nimid");
            if($RC != NIME_OK) {
                my $errorTxt = nimError2Txt($RC);
                print STDERR "Failed to generate alarm, RC => $RC :: $errorTxt\n";
                nimLog(2, "Failed to generate alarm, RC => $RC :: $errorTxt");
            }
            ciClose($hCI);
        }
        else {
            # Generate Alarm PDS
            my ($PDSAlarm, $nimid) = src::utils::generateAlarm("alarm", {
                robot       => $hAlarm->{device},
                source      => $hAlarm->{source},
                met_id      => $hAlarm->{met_id} || "",
                dev_id      => $hAlarm->{dev_id},
                hubName     => $localAgent->{hubname},
                domain      => $localAgent->{domain},
                usertag1    => $localAgent->{os_user1},
                usertag2    => $localAgent->{os_user2},
                severity    => $type->{severity},
                subsys      => $type->{subsys},
                origin      => $defaultOrigin,
                probe       => PROBE_NAME,
                message     => $message,
                supp_key    => $suppkey,
                suppression => $suppkey
            });
            print STDOUT "Generate new (raw) alarm with id $nimid\n";
            nimLog(3, "Generate new (raw) alarm with id $nimid");

            # Launch alarm!
            my ($RC) = nimRequest($localAgent->{robotname}, 48001, "post_raw", $PDSAlarm->data);
            if($RC != NIME_OK) {
                my $errorTxt = nimError2Txt($RC);
                print STDERR "Failed to generate alarm, RC => $RC :: $errorTxt\n";
                nimLog(2, "Failed to generate alarm, RC => $RC :: $errorTxt");
            }
        }
    }
    $alarmThreadRunning = 0;
}

# @subroutine startAlarmThread
# @desc Manage and start Alarm thread (work for restarting it too!).
sub startAlarmThread {
    # Create independant thread!
    threads->create(sub {
        # Stop alarm thread if already active!
        if($alarmThreadRunning == 1) {
            $AlarmQueue->enqueue(undef);
            unless($alarmThreadRunning == 0) {
                select(undef, undef, undef, 0.25); # wait 250ms
            }
        }

        eval {
            threads->create(\&alarmsThread)->join;
        };
        if($@) {
            $alarmThreadRunning = 0;
            nimLog(0, $@);
        }
    })->detach;
}

# @subroutine processXMLFiles
# @desc Process XML Files to get Devices and SNMP Profiles
sub processXMLFiles {
    $readXML_open = 1;
    print STDOUT "Entering processXMLFiles() !\n";
    nimLog(3, "Entering processXMLFiles() !");
    my $processXMLFilesTimer = nimTimerCreate();
    nimTimerStart($processXMLFilesTimer);
    my $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY)->import_def('./db/database_definition.sql');

    # Connect to MySQL (optionaly)
    my $devicesUUID = {};
    my $dbh = getMySQLConnector();
    if(defined($dbh)) {
        my $sth = $dbh->prepare("SELECT device_uuid FROM $DecommissionSQLTable");
        $sth->execute();
        while(my $row = $sth->fetchrow_hashref) {
            $devicesUUID->{$row->{device_uuid}} = 0;
        }
    }
    undef $dbh;

    print STDOUT "Start XML File(s) processing !\n";
    nimLog(3, "Start XML File(s) processing !");
    print STDOUT "XML Directory (from CFG) = $XMLDirectory\n";
    nimLog(3, "XML Directory (from CFG) = $XMLDirectory");

    opendir(DIR, $XMLDirectory) or die("Error: Failed to open the root directory /xml\n");
    my @files = sort { (stat $a)[10] <=> (stat $b)[10] } readdir(DIR); # Sort by date (older to recent)
    my $processed_files = 0;
    foreach my $file (@files) {
        next unless ($file =~ m/^.*\.xml$/); # Skip non-xml files
        print STDOUT "XML File detected => $file\n";
        nimLog(3, "XML File detected => $file\n");

        eval {
            my $XML = src::xmlreader->new("$XMLDirectory/$file")->parse($devicesUUID);
            $SQLDB->upsertXMLObject($XML);
            $XML->deleteFile() if $BOOL_DeleteXML == 1;
            $processed_files++;
        };
        nimLog(2, $@) if $@;
        print STDERR $@ if $@;
    }

    nimTimerStop($processXMLFilesTimer);
    my $execution_time = nimTimerDiff($processXMLFilesTimer);
    nimTimerFree($processXMLFilesTimer);
    print STDOUT "Successfully processed $processed_files XML file(s) in ${execution_time}ms !\n";
    nimLog(3, "Successfully processed $processed_files XML file(s) in ${execution_time}ms !");
    $SQLDB->close();
    
    eval {
        hydrateDevicesAttributes() if $updateDevicesAttr == 0;
    };
    if($@) {
        print STDERR $@;
        nimLog(1, $@);
        $updateDevicesAttr = 0;
    }
    $readXML_open = 0;
}

# @subroutine hydrateDevicesAttributes
# @desc Update device attributes (Make SNMP request to get system informations).
sub hydrateDevicesAttributes {
    if($updateDevicesAttr == 1) {
        return;
    }
    $updateDevicesAttr = 1;
    my $hydrateDevicesAttributesTimer = nimTimerCreate();
    nimTimerStart($hydrateDevicesAttributesTimer);
    print STDOUT "Starting hydratation of Devices attributes\n";
    nimLog(3, "Starting hydratation of Devices attributes");

    # Get all pollable devices from SQLite!
    my $SQLDB           = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
    my $threadQueue     = Thread::Queue->new();
    my $pollableResponseQueue   = Thread::Queue->new();
    $threadQueue->enqueue($_) for @{ $SQLDB->pollable_devices() };
    $threadQueue->enqueue($_) for @{ $SQLDB->unpollable_devices() };
    $SQLDB->close();

    # If threadQueue is empty exit method!
    my $QPending = $threadQueue->pending();
    if($QPending == 0) {
        print STDOUT "No devices to be polled (health_check), Exiting hydrateDevicesAttributes() method!\n";
        nimLog(2, "No devices to be polled (health_check), Exiting hydrateDevicesAttributes() method!");
        $updateDevicesAttr = 0;
        return;
    }

    # Re-allocate right number of threads!
    my $t_healthThreadsCount = $HealthThreads;
    if($QPending < $t_healthThreadsCount) {
        $t_healthThreadsCount = $threadQueue->pending();
        print STDOUT "Adjusting (in running context) health_threads count to $t_healthThreadsCount\n";
        nimLog(2, "Adjusting (in running context) health_threads count to $t_healthThreadsCount");
    }

    my $pollingThread = sub {
        print STDOUT "Health Polling thread started\n";
        nimLog(3, "Health Polling thread started");

        my $SQLDB       = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        my $snmpManager = src::snmpmanager->new();
        while ( defined ( my $Device = $threadQueue->dequeue() ) ) {
            my $result          = $snmpManager->snmpSysInformations($Device);
            my $isPollable      = ref($result) eq "HASH" ? 1 : 0;
            my $isPollableStr   = $isPollable ? "true" : "false";
            print STDOUT "Device $Device->{name} (uuid: $Device->{dev_uuid}) has been detected has pollable: $isPollableStr\n";
            nimLog(2, "Device $Device->{name} (uuid: $Device->{dev_uuid}) has been detected has pollable: $isPollableStr");

            $pollableResponseQueue->enqueue({
                uuid        => $Device->{dev_uuid},
                pollable    => $isPollable
            });

            # Generate Reachability QoS
            my $hCI = ciOpenRemoteDevice("2.1", $Device->{name}, $Device->{ip});
            my $QOS = nimQoSCreate("QOS_REACHABILITY", $Device->{name}, $HealthInterval, -1);
            ciBindQoS($hCI, $QOS, "2.1:1");
            nimQoSSendValue($QOS, "reachability", $isPollable);
            ciUnBindQoS($QOS);
            nimQoSFree($QOS);

            # Update SQLite attributes and trigger an Alarm (clear or not).
            $SQLDB->checkAttributes($result, $Device) if $isPollable == 1;
            $AlarmQueue->enqueue({
                type    => $isPollable ? "device_responding" : "device_not_responding",
                device  => $Device->{name},
                source  => $Device->{ip},
                dev_id  => $Device->{dev_id},
                hCI     => $hCI,
                metric  => "2.1:1"
            });
        }
        print STDOUT "Health Polling thread finished\n";
        $SQLDB->close();
        nimLog(3, "Health Polling thread finished");
    };

    # Wait for polling threads
    my @thr = map {
        threads->create(\&$pollingThread);
    } 1..$t_healthThreadsCount;
    for(my $i = 0; $i < $t_healthThreadsCount; $i++) {
        $threadQueue->enqueue(undef);
    }
    $_->join() for @thr;
    $pollableResponseQueue->enqueue(undef);

    # Update pollable values!
    my $SQLDB       = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
    $SQLDB->{DB}->begin_work;
    while ( defined ( my $Device = $pollableResponseQueue->dequeue() ) ) {
        $SQLDB->updatePollable($Device->{uuid}, $Device->{pollable});
    }
    $SQLDB->{DB}->commit;
    $SQLDB->close();

    nimTimerStop($hydrateDevicesAttributesTimer);
    my $execution_time = nimTimerDiff($hydrateDevicesAttributesTimer);
    nimTimerFree($hydrateDevicesAttributesTimer);
    print STDOUT "Successfully hydrate devices attributes in ${execution_time}ms !\n";
    nimLog(3, "Successfully hydrate devices attributes in ${execution_time}ms !");
    $updateDevicesAttr = 0;
}

# @subroutine removeDevices
# @desc Remove Devices from probe!
sub removeDevices {
    $removeDevicesRunning = 1;
    print STDOUT "Remove Devices method triggered!\n";
    nimLog(3, "Remove Devices method triggered!");

    # Connect to MySQL!
    my $dbh = getMySQLConnector();
    if(!defined($dbh)) {
        nimLog(1, "Exiting removeDevices()... MySQL database KO");
        $removeDevicesRunning = 0;
        return;
    }

    my $sth = $dbh->prepare("SELECT device_uuid FROM $DecommissionSQLTable");
    $sth->execute();
    my $devicesUUID = {};
    while(my $row = $sth->fetchrow_hashref) {
        $devicesUUID->{$row->{device_uuid}} = 0;
    }
    undef $sth;
    undef $dbh;

    # Stop if we have no devicesUUID!
    if(scalar keys %{ $devicesUUID } == 0) {
        nimLog(3, "No devices to remove has been found in the MySQL database");
        return;
    }
    
    my @deviceToRemove = ();
    my $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY)->import_def('./db/database_definition.sql');
    my $sth = $SQLDB->{DB}->prepare("SELECT uuid, snmp_uuid FROM nokia_ipsla_device WHERE is_active=1");
    $sth->execute();
    while(my $row = $sth->fetchrow_hashref) {
        push(@deviceToRemove, {
            snmp_uuid => $row->{snmp_uuid},
            uuid => $row->{uuid},
        }) if defined($devicesUUID->{$row->{uuid}});
    }
    undef $sth;
    undef $devicesUUID;

    # Remove Device from SQLite table!
    $SQLDB->{DB}->begin_work;
    foreach(@deviceToRemove) {
        nimLog(3, "Remove (Decommission) of the Device with UUID => $_->{uuid}");
        $SQLDB->{DB}->prepare('UPDATE nokia_ipsla_device SET is_active=? WHERE uuid=?')->execute(0, $_->{uuid});
        $SQLDB->{DB}->prepare('DELETE FROM nokia_ipsla_device_attr WHERE dev_uuid=?')->execute($_->{uuid});
        # TODO: DECOM SNMP ? Metrics?
    }
    $SQLDB->{DB}->commit;
    $SQLDB->close();
}

# @subroutine updateInterval
# @desc Launch a new provisioning interval
sub updateInterval {
    # Return if updateInterval is already launched!
    if($readXML_open == 1) {
        return;
    }
    print STDOUT "Triggering provisioning interval...\n";
    nimLog(3, "Triggering provisioning interval...");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&processXMLFiles)->join;
        };
        if($@) {
            $readXML_open = 0;
            nimLog(0, $@);
        }
    })->detach;

    # Reset interval
    $T_CheckInterval = nimTimerCreate();
    nimTimerStart($T_CheckInterval);
}

# @subroutine healthPollingInterval
# @desc Health polling interval (will set device.is_pollable to 1 or 0)
sub healthPollingInterval {
    # Return if updateDevicesAttr is already launched!
    if($updateDevicesAttr == 1) {
        return;
    }

    print STDOUT "Triggering health polling interval\n";
    nimLog(3, "Triggering health polling interval");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&hydrateDevicesAttributes)->join;
        };
        if($@) {
            $updateDevicesAttr = 0;
            nimLog(0, $@);
        }
    })->detach;

    # Reset interval
    $T_HealthInterval = nimTimerCreate();
    nimTimerStart($T_HealthInterval);
}

# @subroutine removeDevicesInterval
# @desc Remove devices interval
sub removeDevicesInterval {
    # Return if updateDevicesAttr is already launched!
    if($removeDevicesRunning == 1) {
        return;
    }
    $removeDevicesRunning = 1;

    print STDOUT "Triggering remove devices interval\n";
    nimLog(3, "Triggering remove devices interval");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&removeDevices)->join;
        };
        if($@) {
            $removeDevicesRunning = 0;
            nimLog(0, $@);
        }
    })->detach;

    # Reset interval
    $T_RemoveDevicesInterval = nimTimerCreate();
    nimTimerStart($T_RemoveDevicesInterval);
}

# @subroutine snmpPollingInterval
# @desc Snmp polling interval
sub snmpPollingInterval {
    print STDOUT "Triggering snmp polling interval\n";
    nimLog(3, "Triggering snmp polling interval");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&polling)->join;
        };
        if($@) {
            print STDERR $@."\n";
            nimLog(0, $@);
        }
    })->detach;

    # Reset interval
    $T_PollingInterval = nimTimerCreate();
    nimTimerStart($T_PollingInterval);
}

# @subroutine startAlarmMetricHandlerThread
# @desc Thread to handle all Metric QoS history
sub startAlarmMetricHandlerThread {
    print STDOUT "Triggering QoS history metric thread\n";
    nimLog(3, "Triggering QoS history metric thread");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&QoSHistory)->join;
        };
        if($@) {
            print STDERR $@."\n";
            nimLog(0, $@);
        }
    })->detach;
}

# @subroutine QoSHistory
# @desc Handle QoSHistory
sub QoSHistory {
    # TODO: Request SQLite view
}

# @callback get_info
# @desc Get information about how run the probe
sub get_info {
    my ($hMsg) = @_;
    print STDOUT "get_info callback triggered!\n";
    nimLog(3, "get_info callback triggered!");

    my $PDS = Nimbus::PDS->new(); 
    $PDS->put("info", "Probe received callback: OK", PDS_PCH);
    $PDS->put("provisioning_running", $readXML_open, PDS_INT);
    $PDS->put("health_running", $updateDevicesAttr, PDS_INT);
    $PDS->put("decommission_running", $removeDevicesRunning, PDS_INT);

    nimSendReply($hMsg, NIME_OK, $PDS->data);
}

# @callback force_provisioning
# @desc Force an update (provisioning) interval (work only if no interval are running)
sub force_provisioning {
    my ($hMsg) = @_;
    my $PDS = Nimbus::PDS->new(); 

    # Return error if provisioning is already running!
    if($readXML_open == 1) {
        $PDS->put("info", "provisioning interval is running!", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    $PDS->put("info", "provisioning interval started successfully!");
    nimSendReply($hMsg, NIME_OK, $PDS->data);
    updateInterval();
}

# @callback remove_device
# @desc Remove a given device from the probe
sub remove_device {
    my ($hMsg, $deviceName) = @_;
    nimLog(3, "Callback remove_device triggered");
    nimLog(3, "Action requested: Remove device => $deviceName");

    # Connect to the SQLite
    my $SQLDB = src::dbmanager->new(
        './db/nokia_ipsla.db',
        $CRED_KEY
    )->import_def('./db/database_definition.sql');
    my $sth = $SQLDB->{DB}->prepare('SELECT uuid FROM nokia_ipsla_device WHERE name=?');
    $sth->execute($deviceName);
    my $uuid;
    while(my $row = $sth->fetchrow_hashref) {
        $uuid = $row->{uuid};
    }
    if(!defined($uuid)) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error", "Unknow local device with name $deviceName", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    # Connect to MySQL
    my $dbh = getMySQLConnector();
    if(!defined($dbh)) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error", "Failed to establish a connection to the MySQL database!", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    my $insertSth = $dbh->prepare("INSERT INTO $DecommissionSQLTable (device_uuid) VALUES (?)");
    $insertSth->execute($uuid);
    nimSendReply($hMsg, NIME_OK);
}

# @callback force_decommission
# @desc Force decomission interval
sub force_decommission {
    my ($hMsg) = @_;
    nimLog(3, "Callback force_decommission triggered");
    if($removeDevicesRunning == 1) {
        my $PDS = Nimbus::PDS->new();
        $PDS->put("info", "remove devices interval is running!", PDS_PCH);
        nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }
    else {
        removeDevicesInterval();
        nimSendReply($hMsg, NIME_OK);
    }

}

# @callback timeout
# @desc NimSoft probe timeout (run as interval)
sub timeout {
    # Check snmp polling interval (!high-priority)
    snmpPollingInterval() if nimTimerDiffSec($T_PollingInterval) >= $PollingInterval;

    # Check if defined (provisioning) interval is elapsed
    updateInterval() if nimTimerDiffSec($T_CheckInterval) >= $ProvisioningInterval;

    # Check health polling interval
    healthPollingInterval() if nimTimerDiffSec($T_HealthInterval) >= $HealthInterval;

    # Check remove devices interval
    removeDevicesInterval() if nimTimerDiffSec($T_RemoveDevicesInterval) >= $RemoveDevicesInterval;
}

# @callback restart
# @desc Run when the probe is restarted!
sub restart {
    print STDOUT "Probe restart callback triggered... No effects (please deactivate/re-activate)\n";
    nimLog(3,"Probe restart callback triggered... No effects (please deactivate/re-activate)");
}

# @subroutine polling
# @desc SNMP Polling phase
sub polling {
    print STDOUT "SNMP Polling triggered!\n";
    nimLog(3, "SNMP Polling triggered!");

    # Manage QoS
    if($QoSHandlers->pending() > 0) {
        print "Insert all recolted QoS in the SQLite DB!\n";
        nimLog(2, "Insert all recolted QoS in the SQLite DB!");
        my $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        $SQLDB->{DB}->begin_work;
        while ( defined(my $QoSRow = $QoSHandlers->dequeue_nb()) ) {
            eval {
                $SQLDB->{DB}->prepare(
                    "INSERT INTO nokia_ipsla_metrics (name, device_name, probe, type, value, time) VALUES (?, ?, ?, ?, ?, ?)"
                )->execute(
                    $QoSRow->{name},
                    $QoSRow->{device},
                    $QoSRow->{probe},
                    $QoSRow->{type},
                    $QoSRow->{value},
                    $QoSRow->{time}
                );
            };
            nimLog(1, $@) if $@;
        }
        eval {
            $SQLDB->{DB}->commit;
        };
        nimLog(0, $@) if $@;
        $SQLDB->close();
        startAlarmMetricHandlerThread();
    }

    my $timeline = threads->create(sub {
        # Get devices
        my $SQLDB   = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        my @devices = @{ $SQLDB->pollable_devices() };
        $SQLDB->close();

        # Establish timeline
        my $totalTimeMs = (($PollingInterval / 100) * 90) * 1000;
        my $totalEquipments = scalar @devices;
        my $poolPollingInterval = floor($totalTimeMs / $totalEquipments) / 1000;

        print "SNMP Pool Polling limitation (ms) => $totalTimeMs ms\n";
        nimLog(3, "SNMP Pool Polling limitation (ms) => $totalTimeMs ms");
        print "SNMP Pool Polling interval => $poolPollingInterval s\n";
        nimLog(3, "SNMP Pool Polling interval => $poolPollingInterval s");

        my $start = time();
        while($totalEquipments > 0) {
            $deviceHandlerQueue->enqueue(pop(@devices));
            $totalEquipments--;
            if($totalEquipments != 0) {
                select(undef, undef, undef, $poolPollingInterval);
            }
        }
        $deviceHandlerQueue->enqueue(undef);

        my $polling_time = sprintf("%.2f", time() - $start);
        nimLog(3, "SNMP Polling execution time: $polling_time s");
        print STDOUT "SNMP Polling execution time: $polling_time s\n";
        return;
    });

    threads->create(sub {
        print STDOUT "SNMP Pool-polling thread started!\n";
        nimLog(3, "SNMP Pool-polling thread started!");
        my $startTime = localtime(time);
        $startTime -= $PollingInterval;
        print STDOUT "Start time => $startTime\n";

        # read (templates) configuration
        my $CFG = Nimbus::CFG->new(CFG_FILE);
        my $templates       = {};
        foreach my $tableName (keys %{ $CFG->{templates} }) {
            my @ProbesFilters = ();
            foreach my $filterId (keys %{ $CFG->{templates}->{$tableName} }) {
                my $hTest   = {};
                my @fields  = ();
                foreach my $fieldKey (keys %{ $CFG->{templates}->{$tableName}->{$filterId} }) {
                    if($fieldKey eq "saa_name") {
                        my $saaName = $CFG->{templates}->{$tableName}->{$filterId}->{$fieldKey};
                        $hTest->{"nameExpr"} = qr/$saaName/;
                    }
                    else {
                        push(@fields, $fieldKey) if $CFG->{templates}->{$tableName}->{$filterId}->{$fieldKey}->{active} eq "yes";
                    }
                }
                $hTest->{fields} = \@fields;
                push(@ProbesFilters, $hTest);
            }
            $templates->{$tableName} = \@ProbesFilters;
        }

        # Create context variable!
        my $context = {
            startTime => $startTime,
            templates => $templates
        };

        while ( defined(my $device = $deviceHandlerQueue->dequeue()) ) {
            threads->create(\&snmpWorker, $context, $device)->detach();
        }
        print STDOUT "SNMP Pool-polling finished!\n";
        nimLog(3, "SNMP Pool-polling finished!");
    })->detach();
    $timeline->join();

    return;
}

# @subroutine snmpWorker
# @desc SNMP (Polling) Worker
sub snmpWorker {
    my ($context, $device) = @_;
    my $pollTime = localtime(time);
    print STDOUT "Handle device $device->{name}\n";
    nimLog(3, "Handle device $device->{name}");

    # Get SNMP Session
    my $snmpSession = src::snmpmanager->new()->initSnmpSession($device);
    if(!defined($snmpSession)) {
        nimLog(1, "Exiting snmpWorker() thread for device $device->{name}");
        threads->exit();
    }

    # Foreach all templates tests!
    foreach my $snmpTable (keys %{ $context->{templates} }) {
        my $result;
        my $getTableExecutionTime = nimTimerCreate();
        nimTimerStart($getTableExecutionTime);
        eval {
            my $oid     = &SNMP::translateObj($snmpTable);
            $result     = $snmpSession->gettable($oid, nogetbulk => 1);
        };
        if($@ || !defined($result)) {
            nimLog(1, "Failed to execute gettable on device $device->{name} for table $snmpTable");
            $AlarmQueue->enqueue({
                type    => "gettable_fail",
                device  => $device->{name},
                source  => $device->{ip},
                dev_id  => $device->{dev_id},
                payload => {
                    table => $snmpTable
                }
            });
            threads->exit();
        }
        else {
            nimTimerStop($getTableExecutionTime);
            my $executionTimeMs = nimTimerDiff($getTableExecutionTime);
            nimTimerFree($getTableExecutionTime);

            print STDOUT "Successfully gettable $snmpTable on device $device->{name} in ${executionTimeMs}ms\n";
            nimLog(3, "Successfully gettable $snmpTable on device $device->{name} in ${executionTimeMs}ms");
        }

        # TODO: Aggregate rows for History type
        if($snmpTable eq "tmnxOamPingHistoryTable") {
        }

        my $hCI = ciOpenRemoteDevice("2.1", $device->{name}, $device->{ip});
        foreach my $testOid (keys %{ $result }) {
            my $testNameStr = src::utils::ascii_oid($testOid, 0);
            OID: foreach my $filter (@{ $context->{templates}->{$snmpTable} }) {
                next unless $testNameStr =~ $filter->{nameExpr};
                my $currTest = $result->{$testOid};
                nimLog(4, "Matching test name => $testNameStr");
                print STDOUT "Matching test name => $testNameStr\n";
                
                # Get timefield
                my $timeField;
                if($snmpTable eq "tmnxOamPingHistoryTable") {
                    $timeField = $currTest->{"tmnxOamPingHistoryTime"};
                }
                elsif($snmpTable eq "tmnxOamPingResultsTable") {
                    $timeField = $currTest->{"tmnxOamPingResultsLastGoodProbe"};
                }

                # Handle timer
                {   
                    my @group       = split(",",$timeField);
                    my @f1          = split('-', $group[0]);
                    my @f2          = split(':', $group[1]);
                    my $timeDate    = sprintf(
                        "%02d:%02d:%02d %02d:%02d:%02d",
                        $f1[0], $f1[1], $f1[2], $f2[0], $f2[1], $f2[2]
                    );
                    my $format = "%Y:%m:%d %H:%M:%S";
                    eval {
                        my $diff = Time::Piece->strptime($context->{startTime}, $format) - Time::Piece->strptime($timeDate, $format);
                        if($diff > 0) {
                            nimLog(3, "Skipping test (last run outdated) $snmpTable->$testNameStr on device $device->{name}");
                            last OID;
                        }
                    };
                    print STDERR $@ if $@;
                }

                foreach my $fieldName (@{ $filter->{fields} }) {
                    next unless defined($currTest->{$fieldName});
                    if(!defined($SnmpQoSSchema->{$fieldName})) {
                        nimLog(2, "Unknow QoS type for field $fieldName, table: $snmpTable, device: $device->{name}");
                        next;
                    }
                    my $QoSType     = $SnmpQoSSchema->{$fieldName};
                    my $fieldValue  = $SnmpQoSValueParser->{$QoSType->{unit}}($currTest->{$fieldName});
                    
                    # Create QoS
                    my $QoSTimestamp = time();
                    my $QOS = nimQoSCreate("QOS_$fieldName", $device->{name}, $PollingInterval, -1);
                    ciBindQoS($hCI, $QOS, $fieldName);
                    nimQoSSendValue($QOS, $testNameStr, $fieldValue);
                    ciUnBindQoS($QOS);
                    nimQoSFree($QOS);

                    # Enqueue QoS
                    # $QoSHandlers->enqueue({
                    #     name    => "QOS_$fieldName",
                    #     type    => $QoSType->{unit},
                    #     value   => $fieldValue,
                    #     probe   => $testNameStr,
                    #     device  => $device->{name},
                    #     time    => $QoSTimestamp
                    # });
                }
                last OID;
            }
        }
        ciClose($hCI);
    }

    print STDOUT "Finished device $device->{name}\n";
    nimLog(3, "Finished device $device->{name}");
}

# Start alarm thread
startAlarmThread();

# Read Nimbus configuration
processProbeConfiguration();

# Create the Nimsoft probe!
$sess = Nimbus::Session->new(PROBE_NAME);
$sess->setInfo(VERSION, "Nokia_ipsla collector probe");

# Register Nimsoft probe to his agent
if ( $sess->server (NIMPORT_ANY, \&timeout, \&restart) == NIME_OK ) {
    # Register callbacks (by giving global function name).
    nimLog(3, "Adding probe callbacks...");
    $sess->addCallback("get_info");
    $sess->addCallback("force_provisioning");
    $sess->addCallback("remove_device", "deviceName");
    $sess->addCallback("force_decommission");

    # Set timeout to 1000ms (so one second).
    nimLog(3, "Dispatch timeout callback at 1,000ms");
    $sess->dispatch(1000);
}