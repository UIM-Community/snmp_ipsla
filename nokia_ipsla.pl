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
use List::Util qw( min max sum );

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
    VERSION => "1.8.2"
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
my $STR_RobotName: shared = "";
my $sess;

# Set array average!
sub mean { 
    return @_ ? sum(@_) / @_ : 0
}

# SNMP QoS Parser routines
# This table has been created to parse SNMP output by values
# For example some values are return like this "45 microseconds", so we only want to extract "45"
# Only two values are supported by the probe (Microseconds and Boolean).
my $SnmpQoSValueParser = {
    Microseconds => sub {
        my ($strValue) = @_;
        my @matches = $strValue =~ /(.*)\smicroseconds/g;
        return $matches[0];
    },
    State => sub {
        my ($strValue) = @_;
        return $strValue eq "success";
    },
    count => sub {
        my ($strValue) = @_;
        my @matches = $strValue =~ /^([0-9]+)/g;
        return $matches[0];
    }
};

# Hash table to retrieve metricId by the metric name
# This table has been created because of the difficulties to retrieve these with the $SnmpQoSSchema table
my $QOSMetrics = {
    QOS_RESPONSEPATHTEST_TESTRUNRESULT => "9.1.2.1:0",
    QOS_RESPONSEPATHTEST_MINIMUMRTT => "9.1.2.1:1",
    QOS_RESPONSEPATHTEST_AVERAGERTT => "9.1.2.1:3",
    QOS_RESPONSEPATHTEST_MAXIMUMRTT => "9.1.2.1:2",
    QOS_RESPONSEPATHTEST_MINIMUMTT => "9.1.2.1:4",
    QOS_RESPONSEPATHTEST_AVERAGETT => "9.1.2.1:10",
    QOS_RESPONSEPATHTEST_MAXIMUMTT => "9.1.2.1:5",
    QOS_RESPONSEPATHTEST_JITTERIN => "9.1.2.1:9",
    QOS_RESPONSEPATHTEST_JITTEROUT => "9.1.2.1:8",
    QOS_RESPONSEPATHTEST_RTJITTER => "9.1.2.1:12",
    QOS_RESPONSEPATHTEST_MINIMUMTTIN => "9.1.2.1:6",
    QOS_RESPONSEPATHTEST_AVERAGETTIN => "9.1.2.1:11",
    QOS_RESPONSEPATHTEST_MAXIMUMTTIN => "9.1.2.1:7",
    QOS_RESPONSEPATHTEST_PROBEFAILURES => "9.1.2.1:13",
    QOS_RESPONSEPATHTEST_SENTPROBES => "9.1.2.1:14"
};

# Complete QoS Schema to publish for the probe!
# These are published in Nimsoft by the processProbeConfiguration method
my $SnmpQoSSchema = {
    tmnxOamPingResultsTestRunResult => {
        name => "QOS_RESPONSEPATHTEST_TESTRUNRESULT",
        unit => "State",
        short => "",
        group => "QOS_NETWORK",
        description => "Test RUN Result",
        flags => 1,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:0"
    },
    tmnxOamPingResultsMinRtt => {
        name => "QOS_RESPONSEPATHTEST_MINIMUMRTT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Minimum Round Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:1"
    },
    tmnxOamPingResultsAverageRtt => {
        name => "QOS_RESPONSEPATHTEST_AVERAGERTT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Average Round Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:3"
    },
    tmnxOamPingResultsMaxRtt => {
        name => "QOS_RESPONSEPATHTEST_MAXIMUMRTT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Maximum Round Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:2"
    },
    tmnxOamPingResultsMinTt => {
        name => "QOS_RESPONSEPATHTEST_MINIMUMTT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Minimum Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:4"
    },
    tmnxOamPingResultsAverageTt => {
        name => "QOS_RESPONSEPATHTEST_AVERAGETT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Average Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:10"
    },
    tmnxOamPingResultsMaxTt => {
        name => "QOS_RESPONSEPATHTEST_MAXIMUMTT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Maximum Trip Time",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:5"
    },
    tmnxOamPingResultsInJitter => {
        name => "QOS_RESPONSEPATHTEST_JITTERIN",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "IN Jitter",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:9"
    },
    tmnxOamPingResultsOutJitter => {
        name => "QOS_RESPONSEPATHTEST_JITTEROUT",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "OUT Jitter",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:8"
    },
    tmnxOamPingResultsRtJitter => {
        name => "QOS_RESPONSEPATHTEST_RTJITTER",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Round Trip Jitter",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:12"
    },
    tmnxOamPingResultsMinInTt => {
        name => "QOS_RESPONSEPATHTEST_MINIMUMTTIN",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Minimum Trip Time IN",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:6"
    },
    tmnxOamPingResultsAverageInTt => {
        name => "QOS_RESPONSEPATHTEST_AVERAGETTIN",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Average Trip Time IN",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:11"
    },
    tmnxOamPingResultsMaxInTt => {
        name => "QOS_RESPONSEPATHTEST_MAXIMUMTTIN",
        unit => "Microseconds",
        short => "us",
        group => "QOS_NETWORK",
        description => "Maximum Trip Time IN",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:7"
    },
    tmnxOamPingResultsProbeFailures => {
        name => "QOS_RESPONSEPATHTEST_PROBEFAILURES",
        unit => "count",
        short => "#",
        group => "QOS_NETWORK",
        description => "Probe failures",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:13"
    },
    tmnxOamPingResultsSentProbes => {
        name => "QOS_RESPONSEPATHTEST_SENTPROBES",
        unit => "count",
        short => "#",
        group => "QOS_NETWORK",
        description => "Probes sent",
        flags => 0,
        ci_type => "9.1.2.1",
        metric_name => "9.1.2.1:14"
    }
};

# Shared Queues. These are used among multiple threads to publish/exchange data
my $AlarmQueue = Thread::Queue->new();
my $deviceHandlerQueue = Thread::Queue->new();
my $QoSHandlers = Thread::Queue->new();

# Execute the routine scriptDieHandler if the script die for any reasons
$SIG{__DIE__} = \&scriptDieHandler;

# @subroutine scriptDieHandler
# @desc Routine triggered when the script have to die
sub scriptDieHandler {
    my ($err) = @_;
    print STDERR "$err\n";
    nimLog(0, "$err");
    exit(1);
}

# @subroutine getMySQLConnector
# @desc Connect the Perl DBI Driver to the MySQL database. It will return undef if the connection failed !
sub getMySQLConnector {
    nimLog(3, "Initialize MySQL connection: (CS: $DB_ConnectionString)");
    my $dbh = DBI->connect($DB_ConnectionString, $DB_User, $DB_Password);
    if(!defined($dbh)) {
        print STDERR "Failed to connect to the MySQL Database...\n";
        nimLog(1, "Failed to connect to the MySQL Database...");
    }
    else {
        nimLog(3, "Successfully connected to MySQL database!");
        print STDOUT "Successfully connected to MySQL database!\n";
    }

    return $dbh;
}

# @subroutine openLocalDB
# @desc Open LocalDB (SQLite) properly. Return undef if the connector fail.
sub openLocalDB {
    my ($importDef) = @_;
    my $SQLDB;

    eval {
        $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        if ($importDef == 1) {
            $SQLDB->import_def('./db/database_definition.sql');
        }
    };
    if($@) {
        print STDERR $@;
        nimLog(1, $@);
        return undef;
    }

    return $SQLDB;
}

# @subroutine processProbeConfiguration
# @desc Read/Parse and apply default probe Configuration !
sub processProbeConfiguration {
    # Launch method timer
    my $processProbeConfigurationTime = nimTimerCreate();
    nimTimerStart($processProbeConfigurationTime);

    # Open Configuration File handler
    my $CFG                 = Nimbus::CFG->new(CFG_FILE);

    # Setup section
    my $STR_Login           = $CFG->{"setup"}->{"nim_login"} || "administrator";
    my $STR_Password        = $CFG->{"setup"}->{"nim_password"};
    my $INT_LogLevel        = defined($CFG->{"setup"}->{"loglevel"}) ? $CFG->{"setup"}->{"loglevel"} : 3;
    my $INT_LogSize         = $CFG->{"setup"}->{"logsize"} || 1024;
    my $STR_LogFile         = $CFG->{"setup"}->{"logfile"} || "nokia_ipsla.log";
    scriptDieHandler("Configuration <provisioning> section is not mandatory!") if not defined($CFG->{"provisioning"});

    # Database Section
    my $DBName      = $CFG->{"database"}->{"database"} || "ca_uim";
    my $DBHost      = $CFG->{"database"}->{"host"};
    my $DBPort      = $CFG->{"database"}->{"port"} || 3306;
    $DB_ConnectionString = "DBI:mysql:database=$DBName;host=$DBHost;port=$DBPort";
    $DB_User        = $CFG->{"database"}->{"user"};
    $DB_Password    = $CFG->{"database"}->{"password"};

    # Encrypt/Decrypt CFG Credential keys!
    if($DB_Password =~ /^==/) {
        my $TPassword = substr($DB_Password, 2);
        if (src::utils::isBase64($TPassword)) {
            $DB_Password = nimDecryptString($CRED_KEY, $TPassword);
        }
        else {
            print STDOUT "Failed to detect base64 password for config->database->password \n";
            exit(0);
        }
    }
    else {
        my $CFGNapi = cfgOpen(CFG_FILE, 0);
        my $cValue = "==".nimEncryptString($CRED_KEY, $DB_Password);
        cfgKeyWrite($CFGNapi, "/database/", "password", $cValue); 
        cfgSync($CFGNapi);
        cfgClose($CFGNapi);
    }

    # provisioning Section 
    $XMLDirectory           = $CFG->{"provisioning"}->{"xml_dir"} || "./xml";
    $RemoveDevicesInterval  = $CFG->{"provisioning"}->{"decommission_interval"} || 900;
    $DecommissionSQLTable   = "nokia_ipsla_decommission";
    $ProvisioningInterval   = $CFG->{"provisioning"}->{"provisioning_interval"} || 3600;
    $PollingInterval        = $CFG->{"provisioning"}->{"polling_snmp_interval"} || 300;
    $HealthInterval         = $CFG->{"provisioning"}->{"polling_health_interval"} || 1800;
    $HealthThreads          = $CFG->{"provisioning"}->{"polling_health_threads"} || 3;
    $ProvisioningOnStart    = defined($CFG->{"provisioning"}->{"provisioning_on_start"}) ? $CFG->{"provisioning"}->{"provisioning_on_start"} : 1;
    $BOOL_DeleteXML         = defined($CFG->{"provisioning"}->{"delete_xml_files"}) ? $CFG->{"provisioning"}->{"delete_xml_files"} : 0;

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

    # Send Nimsoft QoS definitions
    nimQoSSendDefinition(
        "QOS_REACHABILITY",
        "QOS_NETWORK",
        "Nokia Network connectivity response",
        "State",
        "",
        NIMQOS_DEF_BOOLEAN
    );
    foreach my $QoSName (keys %{ $SnmpQoSSchema }) {
        my $QoS = $SnmpQoSSchema->{$QoSName};
        print STDOUT "Send QoSDefinition $QoS->{name}\n";
        nimLog(3, "Send QoSDefinition $QoS->{name}");
        nimQoSSendDefinition(
            $QoS->{name},
            $QoS->{group},
            $QoS->{description},
            $QoS->{unit},
            $QoS->{short},
            $QoS->{flags}
        );
    }

    # Stdout the time taken to read the configuration!
    nimTimerStop($processProbeConfigurationTime);
    my $executionTimeMs = nimTimerDiff($processProbeConfigurationTime);
    nimTimerFree($processProbeConfigurationTime);
    print STDOUT "processProbeConfiguration() has been executed in ${executionTimeMs}ms\n";
    nimLog(3, "processProbeConfiguration() has been executed in ${executionTimeMs}ms");

    # Start provisioning if $ProvisioningOnStart is equal to 1
    if($ProvisioningOnStart == 1) {
        print STDOUT "Provisioning on start activated: Triggering updateInterval() method!\n";
        nimLog(3, "Provisioning on start activated: Triggering updateInterval() method!");
        updateInterval();
    }
}

# @subroutine alarmsThread
# @desc Thread responsible for creating and publishing new alarm in the Product
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

    # Wait for new alarm to be publish into the AlarmQueue
    while ( defined ( my $hAlarm = $AlarmQueue->dequeue() ) )  {
        # Verify Alarm Type
        next if not defined($hAlarm->{type});
        next if not defined($Alarm->{$hAlarm->{type}});
        my $type = $Alarm->{$hAlarm->{type}};
        my $severity = defined($hAlarm->{severity}) ? $hAlarm->{severity} : $type->{severity};
        
        print "[ALARM] Receiving new alarm of type: $hAlarm->{type} and severity: $severity\n";
        nimLog(3, "[ALARM] Receiving new alarm of type: $hAlarm->{type} and severity: $severity");

        # Parse and Define alarms variables by merging payload into suppkey & message fields
        my $hVariablesRef = defined($hAlarm->{payload}) ? $hAlarm->{payload} : {};
        $hVariablesRef->{host} = $hAlarm->{device};
        my $suppkey = src::utils::parseAlarmVariable($type->{supp_key}, $hVariablesRef);
        my $message = src::utils::parseAlarmVariable($severity == 0 ? $type->{clear_message} : $type->{message}, $hVariablesRef);
        undef $hVariablesRef;

        if(defined($hAlarm->{hCI})) {
            my $hCI = $hAlarm->{hCI};
            my ($RC, $nimid) = ciAlarm(
                $hCI,
                $hAlarm->{metric},
                $severity,
                $message,
                "",
                Nimbus::PDS->new()->data,
                $type->{subsys},
                $suppkey,
                $hAlarm->{source}
            );
            print STDOUT "[ALARM] (id: $nimid) new CI alarm, severity: $type->{severity}, source: $hAlarm->{source}\n";
            nimLog(3, "[ALARM] (id: $nimid) new CI alarm, severity: $type->{severity}, source: $hAlarm->{source}");
            if($RC != NIME_OK) {
                my $errorTxt = nimError2Txt($RC);
                print STDERR "[ALARM] (id: $nimid) Failed to generate alarm, RC => $RC :: $errorTxt\n";
                nimLog(2, "[ALARM] (id: $nimid) Failed to generate alarm, RC => $RC :: $errorTxt");
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

    # Create method timer
    my $processXMLFilesTimer = nimTimerCreate();
    nimTimerStart($processXMLFilesTimer);

    # Open local DB
    my $SQLDB = openLocalDB(1);
    if (!defined($SQLDB)) {
        $readXML_open = 0;
        return;
    }

    # Connect to MySQL (optionaly)
    my $devicesUUID = {};
    eval {
        my $dbh = getMySQLConnector();
        if(defined($dbh)) {
            my $sth = $dbh->prepare("SELECT device FROM $DecommissionSQLTable");
            $sth->execute();
            while(my $row = $sth->fetchrow_hashref) {
                $devicesUUID->{$row->{device}} = 0;
            }
        }
    };
    if ($@) {
        print STDERR $@;
        nimLog(1, $@);
    }

    print STDOUT "Start XML File(s) processing !\n";
    nimLog(3, "Start XML File(s) processing !");
    print STDOUT "XML Directory (from CFG) = $XMLDirectory\n";
    nimLog(3, "XML Directory (from CFG) = $XMLDirectory");

    opendir(DIR, $XMLDirectory) or die("Error: Failed to open the root directory /xml\n");
    my @files = sort { (stat $a)[10] <=> (stat $b)[10] } readdir(DIR); # Sort by date (older to recent)

    # Proceed each XML files
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

    if ($processed_files > 0) {
        print STDOUT "Successfully processed $processed_files XML file(s) in ${execution_time}ms !\n";
        nimLog(3, "Successfully processed $processed_files XML file(s) in ${execution_time}ms !");
    }
    else {
        print STDOUT "No local XML files detected!\n";
        nimLog(3, "No local XML files detected!");
    }
    
    # Run hydrateDevicesAttributes only if at least one XML file has been processed!
    if($processed_files > 0) {
        eval {
            hydrateDevicesAttributes() if $updateDevicesAttr == 0;
        };
        if($@) {
            print STDERR $@;
            nimLog(1, $@);
            $updateDevicesAttr = 0;
        }
    }
    $readXML_open = 0;
}

# @subroutine hydrateDevicesAttributes
# @desc Update device attributes (Make SNMP request to get system informations).
sub hydrateDevicesAttributes {
    # Return if one hydratation is already running
    return if $updateDevicesAttr == 1;
    $updateDevicesAttr = 1;

    my $hydrateDevicesAttributesTimer = nimTimerCreate();
    nimTimerStart($hydrateDevicesAttributesTimer);
    print STDOUT "Starting hydratation of Devices attributes\n";
    nimLog(3, "Starting hydratation of Devices attributes");

    # Open local DB
    my $SQLDB = openLocalDB(0);
    if (!defined($SQLDB)) {
        $updateDevicesAttr = 0;
        return;
    }

    # Get all pollable devices from SQLite!
    my $threadQueue     = Thread::Queue->new();
    my $pollableResponseQueue   = Thread::Queue->new();
    $threadQueue->enqueue($_) for @{ $SQLDB->pollable_devices() };
    $threadQueue->enqueue($_) for @{ $SQLDB->unpollable_devices() };

    # If threadQueue is empty, then exit method!
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
        my $tid = threads->tid();
        print STDOUT "[$tid] Health Polling thread started\n";
        nimLog(3, "[$tid] Health Polling thread started");

        # Open local DB
        my $SQLDB = openLocalDB(0);
        return if not defined $SQLDB;

        # Create new SNMP Manager!
        my $snmpManager = src::snmpmanager->new();
        while ( defined ( my $Device = $threadQueue->dequeue() ) ) {
            my $result;
            eval {
                $result = $snmpManager->snmpSysInformations($Device);
            };
            if($@) {
                nimLog(1, "[$tid][$Device->{name}] $@");
                print STDERR "[$tid][$Device->{name}] $@\n";
                next;
            }
            my $isPollable      = ref($result) eq "HASH" ? 1 : 0;
            my $isPollableStr   = $isPollable ? "true" : "false";
            print STDOUT "[$tid][$Device->{name}] is pollable: $isPollableStr\n";
            nimLog(2, "[$tid][$Device->{name}] is pollable: $isPollableStr");

            # Generate Reachability QoS
            my $hCI = ciOpenRemoteDevice("9.1.2", "Reachability", $Device->{ip});
            my $QOS = nimQoSCreate("QOS_REACHABILITY", $Device->{name}, $HealthInterval, -1);
            ciBindQoS($hCI, $QOS, "9.1.2:1");
            nimQoSSendValue($QOS, "reachability", $isPollable);
            ciUnBindQoS($QOS);
            nimQoSFree($QOS);
            ciClose($hCI);

            # Update SQLite attributes and trigger an Alarm (clear or not).
            $SQLDB->checkAttributes($result, $Device->{dev_uuid}) if $isPollable == 1;
            my $hCIAlarm = ciOpenRemoteDevice("9.1.2", $Device->{name}, $Device->{ip});
            $AlarmQueue->enqueue({
                type    => $isPollable ? "device_responding" : "device_not_responding",
                device  => $STR_RobotName,
                source  => $Device->{name},
                dev_id  => $Device->{dev_id},
                hCI     => $hCIAlarm,
                metric  => "9.1.2:0",
                payload => {
                    device  => $STR_RobotName,
                    source  => $Device->{name}
                }
            });

            # Exlude NON-NOKIA IPSLA SNMP Devices
            if ($result->{"sysObjectID"} !~ /^tmnx/) {
                print STDOUT "[$tid][$Device->{name}] Not detected as a NOKIA-IPSLA Device, set is_pollable to 0\n";
                nimLog(2, "[$tid][$Device->{name}] Not detected as a NOKIA-IPSLA Device, set is_pollable to 0");
                $isPollable = 0;
            }
            $pollableResponseQueue->enqueue({
                uuid        => $Device->{dev_uuid},
                pollable    => $isPollable
            });
        }

        print STDOUT "[$tid] Health Polling thread finished\n";
        nimLog(3, "[$tid] Health Polling thread finished");
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
    my $SQLDB = openLocalDB(0);
    if (!defined($SQLDB)) {
        $updateDevicesAttr = 0;
        return;
    }
    $SQLDB->{DB}->begin_work;
    while ( defined ( my $Device = $pollableResponseQueue->dequeue() ) ) {
        $SQLDB->updatePollable($Device->{uuid}, $Device->{pollable});
    }
    $SQLDB->{DB}->commit;

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

    my $sth = $dbh->prepare("SELECT device FROM $DecommissionSQLTable");
    $sth->execute();
    my $devicesNames = {};
    while(my $row = $sth->fetchrow_hashref) {
        $devicesNames->{$row->{device}} = 0;
    }
    undef $sth;
    undef $dbh;

    # Stop if we have no devicesUUID!
    if(scalar keys %{ $devicesNames } == 0) {
        nimLog(3, "No devices to remove has been found in the MySQL database");
        return;
    }
    
    my @deviceToRemove = ();
    
    # Open local DB
    my $SQLDB = openLocalDB(0);
    if (!defined($SQLDB)) {
        $removeDevicesRunning = 0;
        return;
    }
    my $sth = $SQLDB->{DB}->prepare("SELECT name, uuid, snmp_uuid FROM nokia_ipsla_device WHERE is_active=1");
    $sth->execute();
    while(my $row = $sth->fetchrow_hashref) {
        push(@deviceToRemove, {
            snmp_uuid => $row->{snmp_uuid},
            uuid => $row->{uuid},
        }) if defined($devicesNames->{$row->{name}});
    }
    undef $sth;
    undef $devicesNames;

    # Remove Device from SQLite table!
    $SQLDB->{DB}->begin_work;
    foreach(@deviceToRemove) {
        nimLog(3, "Remove (Decommission) of the Device with UUID => $_->{uuid}");
        $SQLDB->{DB}->prepare('UPDATE nokia_ipsla_device SET is_active=? WHERE uuid=?')->execute(0, $_->{uuid});
        $SQLDB->{DB}->prepare('DELETE FROM nokia_ipsla_device_attr WHERE dev_uuid=?')->execute($_->{uuid});
    }
    $SQLDB->{DB}->commit;
    $removeDevicesRunning = 0;
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

# @subroutine startMetricHistoryThread
# @desc Thread to handle all Metric QoS history
sub startMetricHistoryThread {
    print STDOUT "Triggering QoS history metric thread\n";
    nimLog(3, "Triggering QoS history metric thread");

    # Create separated thread to handle provisioning mechanism
    threads->create(sub {
        eval {
            threads->create(\&SNMPMetricsHistory)->join;
        };
        if($@) {
            print STDERR $@."\n";
            nimLog(0, $@);
        }
    })->detach;
}

# @subroutine SNMPMetricsHistory
# @desc Handle alerting on the SNMP metrics history
sub SNMPMetricsHistory {

    # Parse alerting profiles
    my $Profiles = {};
    {
        my $CFG = Nimbus::CFG->new(CFG_FILE);
        my @sections = $CFG->getSections($CFG->{alerting});
        foreach my $secId (@sections) {
            my $sec = $CFG->{alerting}->{$secId};
            my $keys = {};
            my @tmnxKeys = $CFG->getSections($sec);
            foreach my $tmnxKey (@tmnxKeys) {
                my @ret = ();
                my @messages = $CFG->getSections($sec->{$tmnxKey});
                foreach(@messages) {
                    my $threshold = $sec->{$tmnxKey}->{$_}->{threshold};
                    my $active = defined($sec->{$tmnxKey}->{$_}->{active}) ? $sec->{$tmnxKey}->{$_}->{active} : "yes";
                    push(@ret, {
                        threshold => $threshold,
                        message => $_
                    }) if $active eq "yes";
                }
                $keys->{$tmnxKey} = \@ret;
            }
    
            $Profiles->{$secId} = {
                name => qr/$sec->{saa_name}/,
                keys => $keys
            };
        }
    }

    # 2. Get data from SQLite DB
    my $SQLDB;
    eval {
        $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
    };
    die $@ if $@;

    my $sth = $SQLDB->{DB}->prepare(
        "SELECT device_name, dev_id, name, probe, type, source, ROUND(AVG(value), 1) as value FROM nokia_ipsla_metrics GROUP BY device_name, name, probe, type ORDER BY time"
    );
    $sth->execute;
    my @rows = ();
    while(my $row = $sth->fetchrow_hashref) {
        push(@rows, $row);
    }

    # 3. math actions (match testname with regex)
    foreach my $secId (keys %{ $Profiles }) {
        my $regex   = $Profiles->{$secId}->{name};
        my $keys    = $Profiles->{$secId}->{keys};

        foreach my $sql (@rows) {
            next unless $sql->{probe} =~ $regex;
            next unless defined($keys->{$sql->{name}});

            my $qosValue    = $sql->{value};
            my @thresholds  = @{ $keys->{$sql->{name}} };
            my $foundTreshold = 0;

            my @thresholdsValue;
            push(@thresholdsValue, $_->{threshold}) for @thresholds;

            my $curr = {
                threshold => min(@thresholdsValue),
                message => $thresholds[0]->{message}
            };

            # Check for the lowest matched treshold of the list
            foreach(@thresholds) {
                next unless $_->{threshold} <= $qosValue;
                next unless $_->{threshold} >= $curr->{threshold};
                $foundTreshold = 1;
                $curr = $_;
            }

            # Check if we have a clear alarm (if not, just go the next iteration)
            my $severity = $foundTreshold ? undef : 0;

            # Open Remote Device
            nimLog(3, "Throw alarm $sql->{name} - Robot: $STR_RobotName, Device: $sql->{device_name}, severity: $severity, source: $sql->{source}");
            my $hCI = ciOpenRemoteDevice("9.1.2", $sql->{device_name}, $sql->{source});

            # Throw alarm with message
            $AlarmQueue->enqueue({
                type    => $curr->{message},
                device  => $STR_RobotName,
                source  => $sql->{device_name},
                hCI     => $hCI,
                severity => $severity,
                metric  => $QOSMetrics->{$sql->{name}},
                dev_id  => $sql->{dev_id},
                payload => {
                    threshold => $curr->{threshold},
                    device  => $STR_RobotName,
                    source  => $sql->{device_name},
                    qos     => $sql->{name},
                    test    => $sql->{probe},
                    unit    => $sql->{type},
                    value   => $qosValue
                }
            });
        }
    }

    # 4. Clean last rows of each groups
    my $dt = localtime(time) - ($PollingInterval * 3);
    $dt = sprintf(
        "%04d-%02d-%02d %02d:%02d:%02d",
        $dt->year,
        $dt->mon,
        $dt->mday,
        $dt->hour,
        $dt->min,
        $dt->sec
    );
    nimLog(3, "Delete all rows from SQLite db where date < $dt");
    my $deleteSh = $SQLDB->{DB}->prepare(
        "DELETE FROM nokia_ipsla_metrics WHERE datetime(time, 'unixepoch') < ?"
    );
    $deleteSh->execute($dt);
    $deleteSh->finish;
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

    my $SQLDB;
    eval {
        $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
    };
    if($@) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error", "Failed to open local SQLite database!", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

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

    my $insertSth = $dbh->prepare("INSERT INTO $DecommissionSQLTable (device) VALUES (?)");
    $insertSth->execute($deviceName);
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

# @callback active_device
# @desc Active an inactive device
sub active_device {
    my ($hMsg, $deviceName) = @_;
    nimLog(3, "Callback active_device triggered");
    nimLog(3, "Action requested: Active device => $deviceName");

    my $SQLDB;
    eval {
        $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
    };
    if($@) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error", "Failed to open local SQLite database!", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    my $sth = $SQLDB->{DB}->prepare('SELECT uuid FROM nokia_ipsla_device WHERE name=?');
    $sth->execute($deviceName);
    my $deviceUUID;
    while(my $row = $sth->fetchrow_hashref) {
        $deviceUUID = $row->{uuid};
    }
    if(not defined($deviceUUID)) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error", "Unknow local device with name $deviceName", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    # Force is_active field to 1!
    my $uptStmt = $SQLDB->{DB}->prepare('UPDATE nokia_ipsla_device SET is_active=1 WHERE name=?');
    $uptStmt->execute($deviceName);

    nimSendReply($hMsg, NIME_OK);
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
# @desc Triggered when the probe callback "restart" is called.
sub restart {
    print STDOUT "Probe restart callback triggered... No effects (please deactivate/re-activate)\n";
    nimLog(3,"Probe restart callback triggered... No effects (please deactivate/re-activate)");
}

# @subroutine polling
# @desc SNMP Polling cycle thread
sub polling {
    print STDOUT "SNMP Polling triggered!\n";
    nimLog(3, "SNMP Polling triggered!");

    # Insert all SNMP QoS retrieved by the previous polling cycle!
    if($QoSHandlers->pending() > 0) {
        print "Insert all recolted SNMP Polling QoS in the SQLite DB!\n";
        nimLog(2, "Insert all recolted SNMP Polling  QoS in the SQLite DB!");
        my $SQLDB;
        eval {
            $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        };
        die $@ if $@;
        eval {
            $SQLDB->{DB}->begin_work;
            while ( defined(my $QoSRow = $QoSHandlers->dequeue_nb()) ) {
                $SQLDB->{DB}->prepare("INSERT INTO nokia_ipsla_metrics (name, device_name, dev_id, source, probe, type, value, time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)")->execute(
                    $QoSRow->{name},
                    $QoSRow->{device},
                    $QoSRow->{dev_id},
                    $QoSRow->{source},
                    $QoSRow->{probe},
                    $QoSRow->{type},
                    $QoSRow->{value},
                    $QoSRow->{time}
                );
            }
            $SQLDB->{DB}->commit;
        };
        nimLog(0, $@) if $@;
    }

    # Start the thread responsible of triggering new history QoS Alarms
    startMetricHistoryThread();

    # Create a timeline thread
    # This thread will be responsible to time the creation of new SNMP Worker threads
    my $timeline = threads->create(sub {
        
        # Open local DB
        my $SQLDB;
        eval {
            $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $CRED_KEY);
        };
        die $@ if $@;

        # Retrieve only pollable devices
        my @devices = @{ $SQLDB->pollable_devices() };

        # Establish the complete time in Milliseconds
        my $totalTimeMs = (($PollingInterval / 100) * 90) * 1000;

        # Get the total count of devices to poll
        my $deviceCount = scalar @devices;

        # Exit if there is no device to poll
        if ($deviceCount == 0) {
            print "0 SNMP devices to be polled. Exiting polling phase!\n";
            nimLog(2, "0 SNMP devices to be polled. Exiting polling phase!");
            $deviceHandlerQueue->enqueue(undef); # close the queue!
            return;
        }

        # Interval between each SNMP Worker
        my $poolPollingInterval = floor($totalTimeMs / $deviceCount) / 1000;

        print "SNMP Pool Polling limitation (ms) => $totalTimeMs ms\n";
        nimLog(3, "SNMP Pool Polling limitation (ms) => $totalTimeMs ms");
        print "SNMP Pool Polling interval => $poolPollingInterval s\n";
        nimLog(3, "SNMP Pool Polling interval => $poolPollingInterval s");

        my $start = time();
        while($deviceCount > 0) {
            $deviceHandlerQueue->enqueue(pop(@devices));
            $deviceCount--;
            if($deviceCount != 0) {
                select(undef, undef, undef, $poolPollingInterval);
            }
        }
        $deviceHandlerQueue->enqueue(undef);

        my $polling_time = sprintf("%.2f", time() - $start);
        nimLog(3, "SNMP Polling execution time: $polling_time s");
        print STDOUT "SNMP Polling execution time: $polling_time s\n";
        return;
    });

    # This thread will be responsible of creating new SNMP Worker
    threads->create(sub {
        print STDOUT "SNMP Pool-polling thread started!\n";
        nimLog(3, "SNMP Pool-polling thread started!");
        my $startTime = localtime(time) - $PollingInterval;

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

        # Create Worker context variables
        my $context = {
            startTime => $startTime,
            templates => $templates
        };

        # Wait for new Worker
        while ( defined(my $device = $deviceHandlerQueue->dequeue()) ) {
            # Create new Worker with Context & Device
            threads->create(\&snmpWorker, $context, $device)->detach();
        }

        print STDOUT "SNMP Pool-polling finished!\n";
        nimLog(3, "SNMP Pool-polling finished!");
    })->detach();

    # Join timeline thread
    $timeline->join();

    return;
}

# @subroutine snmpWorker
# @desc SNMP (Polling) Worker.
sub snmpWorker {
    my ($context, $device) = @_;
    my $pollTime = localtime(time);
    my $tid = threads->tid();
    print STDOUT "[$tid][$device->{name}] Start worker!\n";
    nimLog(3, "[$tid][$device->{name}] Start worker!");

    # Open SNMP Session
    my $snmpSession = src::snmpmanager->new()->initSnmpSession($device);
    if(!defined($snmpSession)) {
        nimLog(1, "[$tid][$device->{name}] Unable to open snmp session. Exiting worker!");
        print STDERR "[$tid][$device->{name}] Unable to open snmp session. Exiting worker!\n";
        return threads->exit();
    }

    my $snmpTable = "tmnxOamPingResultsTable";
    my $tableOid = &SNMP::translateObj($snmpTable);
    print STDOUT "[$tid][$device->{name}] Requesting table $snmpTable ($tableOid)\n";
    nimLog(3, "[$tid][$device->{name}] Requesting table $snmpTable ($tableOid)");

    my $getTableExecutionTime = nimTimerCreate();
    nimTimerStart($getTableExecutionTime);
    my $result = {};
    eval {
        my $exit = 0;
        my $vb = new SNMP::Varbind(["tmnxOamPingResultsTable"]);
        goto NEXTEVAL if $snmpSession->{ErrorNum};
        do {
            $snmpSession->getnext($vb);
            my @arr = @{$vb};
            if($arr[0] !~ /^tmnxOamPingResults/) {
                $exit = 1;
            }
            else {
                my $testName = src::utils::ascii_oid($arr[1], 0);
                if (!defined($result->{$testName})) {
                    $result->{$testName} = {};
                }
                $result->{$testName}->{$arr[0]} = $arr[2];
            }
        } until ($snmpSession->{ErrorNum} or $exit);
    };
    NEXTEVAL:

    if($snmpSession->{ErrorNum}) {
        nimLog(1, "[$tid][$device->{name}] Failed to get table tmnxOamPingResultsTable: $snmpSession->{ErrorStr}");
        print STDERR "[$tid][$device->{name}] Failed to get table tmnxOamPingResultsTable: $snmpSession->{ErrorStr}\n";

        my $hCIAlarm = ciOpenRemoteDevice("9.1.2", $device->{name}, $device->{ip});
        $AlarmQueue->enqueue({
            type    => "gettable_fail",
            device  => $STR_RobotName,
            source  => $device->{name},
            dev_id  => $device->{dev_id},
            hCI     => $hCIAlarm,
            metric  => "9.1.2:1",
            payload => {
                table => $snmpTable,
                device  => $STR_RobotName,
                source  => $device->{name}
            }
        });

        nimTimerStop($getTableExecutionTime);
        nimTimerFree($getTableExecutionTime);
        return threads->exit();
    }
    else {
        my $hCIAlarm = ciOpenRemoteDevice("9.1.2", $device->{name}, $device->{ip});
        $AlarmQueue->enqueue({
            type    => "gettable_success",
            device  => $STR_RobotName,
            source  => $device->{name},
            dev_id  => $device->{dev_id},
            hCI     => $hCIAlarm,
            metric  => "9.1.2:1",
            payload => {
                table => $snmpTable,
                device  => $STR_RobotName,
                source  => $device->{name}
            }
        });
    }

    nimTimerStop($getTableExecutionTime);
    my $executionTimeMs = nimTimerDiff($getTableExecutionTime);
    nimTimerFree($getTableExecutionTime);
    print STDOUT "[$tid][$device->{name}] Successfully gettable in ${executionTimeMs}ms\n";
    nimLog(3, "[$tid][$device->{name}] Successfully gettable in ${executionTimeMs}ms");

    foreach my $testNameStr (keys %{ $result }) {
        OID: foreach my $filter (@{ $context->{templates}->{$snmpTable} }) {
            next unless $testNameStr =~ $filter->{nameExpr};
            my $currTest = $result->{$testNameStr};
            
            # Get timefield
            my $timeField = $currTest->{"tmnxOamPingResultsLastGoodProbe"};
            if (!defined($timeField)) {
                print STDOUT "[$tid][$device->{name}] Undefined timefield for test $testNameStr\n";
                nimLog(3, "[$tid][$device->{name}] Undefined timefield for test $testNameStr");
                next;
            }

            # Handle timer
            {
                my $timeDate = src::utils::parseSNMPNokiaDate($timeField);
                my $diff = $context->{startTime} - Time::Piece->strptime($timeDate, "%Y:%m:%d %H:%M:%S");
                if($diff > 0) {
                    print STDOUT "[$tid][$device->{name}] Skipping test $testNameStr (last run outdated) \n";
                    nimLog(3, "[$tid][$device->{name}] Skipping test $testNameStr (last run outdated)");
                    last OID;
                }
            }

            my $hCI = ciOpenRemoteDevice("9.1.2", $testNameStr, $device->{ip});
            nimLog(4, "[$tid][$device->{name}] Handle metrics for test with name ($testNameStr)");
            print STDOUT "[$tid][$device->{name}] Handle metrics for test name ($testNameStr)\n";

            foreach my $fieldName (@{ $filter->{fields} }) {
                next unless defined($currTest->{$fieldName});
                next unless defined($SnmpQoSSchema->{$fieldName});

                # Get Type & Value
                my $QoSType     = $SnmpQoSSchema->{$fieldName};
                my $fieldValue  = $SnmpQoSValueParser->{$QoSType->{unit}}($currTest->{$fieldName});
                
                # Create QoS
                my $QoSTimestamp = time();
                my $QOS = nimQoSCreate($QoSType->{name}, $device->{name}, $PollingInterval, -1);
                ciBindQoS($hCI, $QOS, $QoSType->{metric_name});
                nimQoSSendValue($QOS, $testNameStr, $fieldValue);
                ciUnBindQoS($QOS);
                nimQoSFree($QOS);

                # Enqueue QoS
                $QoSHandlers->enqueue({
                    name    => $QoSType->{name},
                    type    => $QoSType->{short},
                    value   => $fieldValue,
                    probe   => $testNameStr,
                    device  => $device->{name},
                    source  => $device->{ip},
                    dev_id  => $device->{dev_id},
                    time    => $QoSTimestamp
                });
            }
            last OID;
            ciClose($hCI);
        }
    }

    print STDOUT "[$tid][$device->{name}] Worker finished!\n";
    nimLog(3, "[$tid][$device->{name}] Worker finished!");
}

# Create XML root directory
{
    my $directory = "xml";
    unless(-e $directory or mkdir $directory) {
        die "Unable to create root directory => $directory\n";
    }
}

# Start alarm thread
startAlarmThread();

# Read Nimbus configuration
processProbeConfiguration();

# Retrieve local Nimsoft robot name
{
    my ($RC, $robotname) = nimGetVarStr(NIMV_ROBOTNAME);
    scriptDieHandler("Unable to retrieve local Nimsoft robot name!\n") if $RC != NIME_OK;
    $STR_RobotName = $robotname;
}

# Log probe version
nimLog(3, "Starting probe with VERSION=".VERSION);
print STDOUT "Starting probe with VERSION=".VERSION."\n";

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
    $sess->addCallback("active_device", "deviceName");
    $sess->addCallback("force_decommission");

    # Set timeout to 1000ms (so one second).
    nimLog(3, "Dispatch timeout callback at 1,000ms");
    $sess->dispatch(1000);
}
