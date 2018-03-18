use lib "/opt/nimsoft/perllib";
use lib "/opt/nimsoft/perl/lib";

# Use Perl core Package(s)
use strict;
use POSIX;
use threads;
use Thread::Queue;
use threads::shared;
use Data::Dumper;

# Use Third-party Package(s)
use Nimbus::API;
use Nimbus::PDS;
use Nimbus::Session;
use Nimbus::CFG;
use Net::SNMP;

# Use internals Package(s)
use src::xmlreader;
use src::dbmanager;
use src::snmpmanager;
use src::utils;
use src::filemap;

# Declare Script CONSTANT(S) and Global(s)
use constant {
    PROBE_NAME => "nokia_ipsla"
};
my $XMLDirectory: shared;
my ($CheckInterval, $T_CheckInterval, $HealthInterval, $T_HealthInterval, $HealthThreads, $ImmediateScan);
my $BOOL_DeleteXML: shared = 1;
my $readXML_open: shared = 0;
my $updateDevicesAttr: shared = 0;
my $databaseKey = "secret_key";

# Unexcepted Script die!
$SIG{__DIE__} = \&scriptDieHandler;

# @subroutine scriptDieHandler
# @desc Routine triggered when the script die
sub scriptDieHandler {
    my ($err) = @_;
    print STDERR "$err\n";
    nimLog(0,"$err");
    exit(1);
}

# @subroutine processProbeConfiguration
# @desc Read and apply default probe Configuration !
sub processProbeConfiguration {
    my $CFG                 = Nimbus::CFG->new("nokia_ipsla.cfg");

    # Setup section
    my $STR_Login           = $CFG->{"setup"}->{"nim_login"} || "administrator";
    my $STR_Password        = $CFG->{"setup"}->{"nim_password"};
    my $INT_LogLevel        = defined($CFG->{"setup"}->{"loglevel"}) ? $CFG->{"setup"}->{"loglevel"} : 5;
    my $INT_LogSize         = $CFG->{"setup"}->{"logsize"} || 1024;
    my $STR_LogFile         = $CFG->{"setup"}->{"logfile"} || "nokia_ipsla.log";

    if(!defined($CFG->{"provisionning"})) {
        scriptDieHandler("Configuration <provisionning> section is not mandatory!");
    }

    # Provisionning Section 
    $XMLDirectory           = $CFG->{"provisionning"}->{"xml_dir"} || "./xml";
    $CheckInterval          = $CFG->{"provisionning"}->{"check_interval"} || 30;
    $HealthInterval         = $CFG->{"provisionning"}->{"polling_health_interval"} || 30;
    $HealthThreads          = $CFG->{"provisionning"}->{"polling_health_threads"} || 3;
    $ImmediateScan          = defined($CFG->{"provisionning"}->{"immediate_scan"}) ? $CFG->{"provisionning"}->{"immediate_scan"} : 0;
    $BOOL_DeleteXML         = defined($CFG->{"provisionning"}->{"delete_xml"}) ? $CFG->{"provisionning"}->{"delete_xml"} : 1;

    my @filters = ();
    if(defined($CFG->{"provisionning"}->{"device_filters"})) {
        foreach my $index (keys $CFG->{"provisionning"}->{"device_filters"}) {
            my $hash = $CFG->{"provisionning"}->{"device_filters"}->{$index};
            foreach my $filterKey (keys $hash) {
                $hash->{$filterKey} = qr/$hash->{$filterKey}/;
            }
            push(@filters, $hash);
        }
    }
    $src::xmlreader::filters = \@filters;

    # Minimum security threshold for CheckInterval
    if($CheckInterval < 5) {
        $CheckInterval = 5;
    }

    # Check XML Directory
    mkdir($XMLDirectory) if -d $XMLDirectory;

    # Login to Nimsoft if required
    nimLogin("$STR_Login","$STR_Password") if defined($STR_Login) && defined($STR_Password);

    # Configure Nimsoft Log!
    nimLogSet($STR_LogFile, '', $INT_LogLevel, NIM_LOGF_NOTRUNC);
    nimLogTruncateSize(512 * $INT_LogSize);
    nimLog(3,"Probe Nokia_ipsla started!"); 

    # Nimsoft timer (init /or/ re-init).
    $T_CheckInterval = nimTimerCreate();
    $T_HealthInterval = nimTimerCreate();
    nimTimerStart($T_CheckInterval);
    nimTimerStart($T_HealthInterval);

    # QoS Definitions
    nimQoSSendDefinition("QOS_REACHABILITY", "QOS_NETWORK", "Network connectivity response", "s", NIMQOS_DEF_NONE);
}
processProbeConfiguration();
my $alarmcache = new src::filemap("alarm_cache.cfg");

# Define alarm messages
my $Alarm = {};
{
    my $CFG = Nimbus::CFG->new("nokia_ipsla.cfg");
    if(defined($CFG->{"messages"})) {
        foreach my $alarmName (keys $CFG->{"messages"}) {
            $Alarm->{$alarmName} = $CFG->{"messages"}->{$alarmName};
        }
    }
};

# Device not responding alarm
my $Msg_DevNotResp_message:shared   = $Alarm->{device_not_responding}->{message};
my $Msg_DevNotResp_subsys:shared    = $Alarm->{device_not_responding}->{subsys};
my $Msg_DevNotResp_suppkey:shared   = $Alarm->{device_not_responding}->{suppkey};
my $Msg_DevNotResp_token:shared     = $Alarm->{device_not_responding}->{token};
my $Msg_DevNotResp_severity:shared  = $Alarm->{device_not_responding}->{severity};

# Device responding alarm
my $Msg_DevResp_message:shared   = $Alarm->{device_responding}->{message};
my $Msg_DevResp_subsys:shared    = $Alarm->{device_responding}->{subsys};
my $Msg_DevResp_suppkey:shared   = $Alarm->{device_responding}->{suppkey};
my $Msg_DevResp_token:shared     = $Alarm->{device_responding}->{token};
my $Msg_DevResp_severity:shared  = $Alarm->{device_responding}->{severity};

# Retrieve robot informations!
my ($RC, $NimResponse) = nimNamedRequest("controller", "get_info", Nimbus::PDS->new);
if($RC != NIME_OK) {
    scriptDieHandler("Failed to establish a communication with the local controller probe!");
}
my $LocalRobot = Nimbus::PDS->new($NimResponse)->asHash();
my $Robot_origin:shared     = $LocalRobot->{origin};
my $Robot_domain:shared     = $LocalRobot->{domain};
my $Robot_usertag1:shared   = $LocalRobot->{os_user1};
my $Robot_usertag2:shared   = $LocalRobot->{os_user2};
my $Robot_name:shared       = $LocalRobot->{robotname};
my $Robot_ip:shared         = $LocalRobot->{robotip};
my $Robot_devid:shared      = $LocalRobot->{robot_device_id};
my $Robot_hubname:shared    = $LocalRobot->{hubname};

if($ImmediateScan == 1) {
    $ImmediateScan = 0;
    updateInterval();
}

# @subroutine processXMLFiles
# @desc Process XML Files to get Devices and SNMP Profiles
sub processXMLFiles {
    $readXML_open = 1;
    my $start = time();
    my $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db', $databaseKey)->import_def('./db/database_definition.sql');

    print STDOUT "Starting XML File(s) processing !\n";
    nimLog(3, "Starting XML File(s) processing !");
    print STDOUT "XMLDirectory = $XMLDirectory\n";
    nimLog(3, "XMLDirectory = $XMLDirectory");

    opendir(DIR, $XMLDirectory) or die("Error: Failed to open the root directory /xml\n");
    my @files = sort { (stat $a)[10] <=> (stat $b)[10] } readdir(DIR); # Sort by date (older to recent)
    my $processed_files = 0;
    foreach my $file (@files) {
        next unless ($file =~ m/^.*\.xml$/); # Skip non-xml files
        print STDOUT "XMLFile => $file\n";
        nimLog(3, "XMLFile => $file\n");

        eval {
            my $XML = src::xmlreader->new("$XMLDirectory/$file")->parse();
            $SQLDB->upsertXMLObject($XML);
            $XML->deleteFile() if $BOOL_DeleteXML == 1;
            $processed_files++;
        };
        nimLog(2, $@) if $@;
        print STDERR $@ if $@;
    }
    my $execution_time = sprintf("%.2f", time() - $start);
    print STDOUT "Successfully processed $processed_files XML file(s) in ${execution_time} seconds !\n";
    nimLog(3, "Successfully processed $processed_files XML file(s) in ${execution_time} seconds !");
    $SQLDB->close();
    
    eval {
        hydrateDevicesAttributes() if $updateDevicesAttr == 0;
    };
    if($@) {
        print STDERR $@;
        nimLog(1,$@);
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
    my $start = time();
    print STDOUT "Starting hydratation of Devices attributes\n";
    nimLog(3, "Starting hydratation of Devices attributes");

    # Get all pollable devices from SQLite!
    my $SQLDB           = src::dbmanager->new('./db/nokia_ipsla.db', $databaseKey);
    my $threadQueue     = Thread::Queue->new();
    my $responseQueue   = Thread::Queue->new();
    $threadQueue->enqueue($_) for @{ $SQLDB->pollable_devices() };
    $threadQueue->enqueue($_) for @{ $SQLDB->unpollable_devices() };
    $SQLDB->close();

    my $devicesHandleCount = 0;
    my $pollingThread;
    $pollingThread = sub {
        print STDOUT "Health Polling thread started\n";
        nimLog(3, "Health Polling thread started");

        my $SQLDB       = src::dbmanager->new('./db/nokia_ipsla.db', $databaseKey);
        my $snmpManager = src::snmpmanager->new();
        while ( defined ( my $Device = $threadQueue->dequeue() ) ) {
            my $result = $snmpManager->snmpSysInformations($Device);
            my $isPollable = ref($result) eq "HASH" ? 1 : 0;
            $responseQueue->enqueue({
                device => $Device->{uuid},
                pollable => $isPollable
            });
            my $QOS = nimQoSCreate("QOS_REACHABILITY", $Device->{name}, 30, -1);
            nimQoSSendValue($QOS, "avg", $isPollable);
            nimQoSFree($QOS);
            my $deviceNameUpdated = $Device->{name};
            $deviceNameUpdated =~ s/-/_/g;
            my $cacheKey = "/${deviceNameUpdated}_not_responding";
            if($isPollable == 1) {
                my $suppkey = src::utils::parseAlarmVariable($Msg_DevResp_suppkey, {
                    host => $Device->{name}
                });
                $SQLDB->checkAttributes($result, $Device);
                if($alarmcache->has($cacheKey)) {
                    my ($PDSAlarm, $nimid) = src::utils::generateAlarm("alarm", {
                        hubName     => $Robot_hubname,
                        robot       => $Device->{name},
                        origin      => "THALES",
                        domain      => $Robot_domain,
                        source      => $Device->{ip},
                        dev_id      => $Device->{dev_id},
                        usertag1    => $Robot_usertag1,
                        usertag2    => $Robot_usertag2,
                        probe       => PROBE_NAME,
                        severity    => $Msg_DevResp_severity,
                        subsys      => $Msg_DevResp_subsys,
                        message     => src::utils::parseAlarmVariable($Msg_DevResp_message, {
                            host => $Device->{name}
                        }),
                        supp_key    => $suppkey,
                        suppression => $suppkey
                    });
                    print STDOUT "Generate new alarm with id $nimid\n";
                    nimLog(3, "Generate new alarm with id $nimid");

                    my ($RC, $Response) = nimRequest($Robot_name, 48001, "post_raw", $PDSAlarm->data);
                    if($RC != NIME_OK) {
                        print STDERR "Failed to generate alarm clear, RC => $RC\n";
                        nimLog(2, "Failed to generate alarm clear, RC => $RC");
                    }
                    $alarmcache->delete($cacheKey) if $RC == NIME_OK;
                }
                $devicesHandleCount++;
            }
            else {
                my $suppkey = src::utils::parseAlarmVariable($Msg_DevNotResp_suppkey, {
                    host => $Device->{name}
                });
                my ($PDSAlarm, $nimid) = src::utils::generateAlarm("alarm", {
                    hubName     => $Robot_hubname,
                    robot       => $Device->{name},
                    origin      => "THALES",
                    domain      => $Robot_domain,
                    source      => $Device->{ip},
                    dev_id      => $Device->{dev_id},
                    usertag1    => $Robot_usertag1,
                    usertag2    => $Robot_usertag2,
                    probe       => PROBE_NAME,
                    severity    => $Msg_DevNotResp_severity,
                    subsys      => $Msg_DevNotResp_subsys,
                    message     => src::utils::parseAlarmVariable($Msg_DevNotResp_message, {
                        host => $Device->{name}
                    }),
                    supp_key    => $suppkey,
                    suppression => $suppkey
                });
                print STDOUT "Generate new alarm with id $nimid\n";
                nimLog(3, "Generate new alarm with id $nimid");

                my ($RC, $Response) = nimRequest($Robot_name, 48001, "post_raw", $PDSAlarm->data);
                if($RC != NIME_OK) {
                    print STDERR "Failed to generate alarm, RC => $RC\n";
                    nimLog(2, "Failed to generate alarm, RC => $RC");
                }
                else {
                    $alarmcache->set($cacheKey, undef);
                }
            }
        }
        print STDOUT "Health Polling thread finished\n";
        $SQLDB->close();
        nimLog(3, "Health Polling thread finished");
    };

    # Wait for polling threads
    my @thr = map {
        threads->create(\&$pollingThread);
    } 1..$HealthThreads;
    for(my $i = 0; $i < $HealthThreads; $i++) {
        $threadQueue->enqueue(undef);
    }
    $_->join() for @thr;
    $responseQueue->enqueue(undef);
    $alarmcache->writeToDisk();

    # Update pollable values!
    my $SQLDB       = src::dbmanager->new('./db/nokia_ipsla.db', $databaseKey);
    $SQLDB->{DB}->begin_work;
    while ( defined ( my $Device = $responseQueue->dequeue() ) ) {
        $SQLDB->updatePollable($Device->{uuid}, $Device->{pollable})
    }
    $SQLDB->{DB}->commit;
    $SQLDB->close();

    my $execution_time = sprintf("%.2f", time() - $start);
    print STDOUT "Successfully hydrate devices attributes in ${execution_time} seconds !\n";
    nimLog(3, "Successfully hydrate devices attributes in ${execution_time} seconds !");
    $updateDevicesAttr = 0;
}

# @subroutine updateInterval
# @desc Launch a new provisionning interval
sub updateInterval {
    # Return if updateInterval is already launched!
    if($readXML_open == 1) {
        return;
    }

    print STDOUT "Triggering automatic XML checking...\n";
    nimLog(3, "Triggering automatic XML checking...");

    # Create separated thread to handle provisionning mechanism
    threads->create(sub {
        eval {
            threads->create(\&processXMLFiles)->join;
        };
        if($@) {
            $readXML_open = 0;
            nimLog(0, $@);
        }
        threads->exit();
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

    # Create separated thread to handle provisionning mechanism
    threads->create(sub {
        eval {
            threads->create(\&hydrateDevicesAttributes)->join;
        };
        if($@) {
            $updateDevicesAttr = 0;
            nimLog(0, $@);
        }
        threads->exit();
    })->detach;

    # Reset interval
    $T_HealthInterval = nimTimerCreate();
    nimTimerStart($T_HealthInterval);
}

# @callback get_info
# @desc Get information about how run the probe
sub get_info {
    my ($hMsg) = @_;
    print STDOUT "get_info callback triggered!\n";
    nimLog(3, "get_info callback triggered!");

    my $PDS = Nimbus::PDS->new(); 
    $PDS->put("info", "Everything is ok!", PDS_PCH);
    $PDS->put("xml_open", $readXML_open, PDS_INT);
    $PDS->put("attr_open", $updateDevicesAttr, PDS_INT);

    nimSendReply($hMsg, NIME_OK, $PDS->data);
}

# @callback force_interval
# @desc Force an update (provisionning) interval (work only if no interval are running)
sub force_interval {
    my ($hMsg) = @_;
    my $PDS = Nimbus::PDS->new(); 

    # Return error if provisionning is already running!
    if($readXML_open == 1) {
        $PDS->put("info", "Provisionning interval is running!", PDS_PCH);
        return nimSendReply($hMsg, NIME_ERROR, $PDS->data);
    }

    $PDS->put("info", "Provisionning interval started successfully!");
    nimSendReply($hMsg, NIME_OK, $PDS->data);
    updateInterval();
}

# @callback remove_device
# @desc Remove a given device from the probe
# TODO: Work method
sub remove_device {
    my ($hMsg) = @_;
    nimLog(3, "Callback remove_device triggered");
    nimSendReply($hMsg);
}

# @callback timeout
# @desc NimSoft probe timeout (run as interval)
sub timeout {
    # Check if defined (provisionning) interval is elapsed
    updateInterval() if nimTimerDiffSec($T_CheckInterval) >= $CheckInterval;

    # Check health polling interval
    healthPollingInterval() if nimTimerDiffSec($T_HealthInterval) >= $HealthInterval;
}

# @callback restart
# @desc Run when the probe is restarted!
sub restart {
    print STDOUT "Probe restarted!\n";
    nimLog(3,"Probe restarted!");

    # Re-read the probe configuration file
    processProbeConfiguration();

    # TODO: Restart required threads!
}

# @subroutine polling
# @desc polling phase
sub polling {
    # TODO: Start thread pool (or re-init it).
}

# Create the Nimsoft probe!
my $sess = Nimbus::Session->new(PROBE_NAME);
$sess->setInfo('1.0', "THALES Nokia_ipsla collector probe");

# Register Nimsoft probe to his agent
if ( $sess->server (NIMPORT_ANY, \&timeout, \&restart) == 0 ) {
    # Register callbacks (by giving global function name).
    $sess->addCallback("get_info");
    $sess->addCallback("force_interval");
    $sess->addCallback("remove_device");

    $sess->dispatch(1000); # Set timeout to 1000ms (so one second).
    polling();
}