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

# Declare Script CONSTANT(S) and Global(s)
use constant {
    PROBE_NAME => "nokia_ipsla"
};
my $XMLDirectory: shared;
my ($CheckInterval, $T_CheckInterval);
my $BOOL_DeleteXML: shared = 1;
my $readXML_open: shared = 0;
my $updateDevicesAttr: shared = 0;

# Unexcepted Script die!
$SIG{__DIE__} = \&scriptDieHandler;
sub scriptDieHandler {
    my ($err) = @_;
    print STDERR "$err\n";
    nimLog(0,"$err");
    exit(1);
}

# Routine to Read and apply default probe Configuration !
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
    my $ImmediateScan       = defined($CFG->{"provisionning"}->{"immediate_scan"}) ? $CFG->{"provisionning"}->{"immediate_scan"} : 0;
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
    nimTimerStart($T_CheckInterval);

    if($ImmediateScan == 1) {
        $ImmediateScan = 0;
        updateInterval();
    }
}
processProbeConfiguration();

# Routine to process XML Files!
sub processXMLFiles {
    $readXML_open = 1;
    my $start = time();
    my $SQLDB = src::dbmanager->new('./db/nokia_ipsla.db')->import_def('./db/database_definition.sql');

    print STDOUT "Starting XML File(s) processing !\n";
    nimLog(3, "Starting XML File(s) processing !");
    print STDOUT "XMLDirectory = $XMLDirectory\n";
    opendir(DIR, $XMLDirectory) or die("Error: Failed to open the root directory /xml\n");
    my @files = sort { (stat $a)[10] <=> (stat $b)[10] } readdir(DIR);
    my $processed_files = 0;
    foreach my $file (@files) {
        next unless ($file =~ m/^.*\.xml$/);
        print STDOUT "XMLFile => $file\n";
        eval {
            my $XML = src::xmlreader->new("$XMLDirectory/$file")->parse();
            $SQLDB->upsertXMLObject($XML);
            $XML->deleteFile() if $BOOL_DeleteXML == 1;
            $processed_files++;
        };
        print STDERR $@ if $@;
    }
    my $execution_time = sprintf("%.2f", time() - $start);
    print STDOUT "Successfully processed $processed_files XML file(s) in ${execution_time} seconds !\n";
    nimLog(3, "Successfully processed $processed_files XML file(s) in ${execution_time} seconds !");
    
    eval {
        hydrateDevicesAttributes($SQLDB);
    };
    if($@) {
        print STDERR $@;
        nimLog(1,$@);
    }
    $SQLDB->close();

    $readXML_open = 0;
}

# Hydrate devices attributes ! 
sub hydrateDevicesAttributes {
    my ($SQLDB) = @_; 

    $updateDevicesAttr = 1;
    my $start = time();
    print STDOUT "Starting hydratation of Devices attributes\n";

    my @devices = @{ $SQLDB->pollable_devices() };
    my $snmpManager = src::snmpmanager->new();
    foreach(@devices) {
        my $result = $snmpManager->snmpSysInformations($_);
        $SQLDB->checkAttributes($result, $_) if defined($result);
    }

    my $execution_time = sprintf("%.2f", time() - $start);
    print STDOUT "Successfully hydrate Devices Attributes in ${execution_time} seconds !\n";
    $updateDevicesAttr = 0;
}

# Routine - Update interval (for provisionning mechanism)
sub updateInterval {
    if($readXML_open == 1) {
        return;
    }
    threads->create(sub {
        eval {
            threads->create(\&processXMLFiles)->join;
        };
        if($@) {
            $readXML_open = 0;
            nimLog(0, $@);
        }
    })->detach;
    $T_CheckInterval = nimTimerCreate();
    nimTimerStart($T_CheckInterval);
}

# CALLBACK <get_info>
sub get_info {
    my ($hMsg) = @_;
    nimLog(3,"get_info callback triggered!"); 
    nimSendReply($hMsg);
}

# CALLBACK <force_interval>
sub force_interval {
    my ($hMsg) = @_;
    if($readXML_open == 1) {
        my $PDS = Nimbus::PDS->new(); 
        $PDS->put("error","XML File(s) processing thread is already running!",PDS_PCH);
        nimSendReply($hMsg, NIME_ERROR, $PDS);
        return;
    }
    nimSendReply($hMsg);
    updateInterval();
}

# CALLBACK <remove_device>
sub remove_device {
    my ($hMsg) = @_;
    nimLog(3, 'Callback remove_device triggered');
    nimSendReply($hMsg);
}

# Probe Timeout
sub timeout {
    if(nimTimerDiffSec($T_CheckInterval) < $CheckInterval) {
        return;
    }
    nimLog(3, "Triggering automatic XML checking...");
    updateInterval();
}

# Probe Restart
sub restart {
    nimLog(3,"Probe restarted!"); 
    processProbeConfiguration();
}

# Create the Nimsoft probe!
my $sess = Nimbus::Session->new(PROBE_NAME);
$sess->setInfo('1.0', "THALES Nokia_ipsla collector probe");
 
if ( $sess->server (NIMPORT_ANY,\&timeout,\&restart) == 0 ) {
    $sess->addCallback("get_info");
    $sess->addCallback("force_interval");
    $sess->addCallback("remove_device");
    $sess->dispatch(1000);
}