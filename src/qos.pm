package src::qos;

# Perl Core package(s)
use strict;
use Exporter qw(import);

# Use third-party
use Nimbus::API;

# Use internal dependencies
use src::utils;

# Export qos functions
our @EXPORT_OK = qw(SendQoSDefinition);

# SNMP Prototype Constructor
sub new {
    my ($class, $QoSParam) = @_;
    return bless({
        name        => $QoSParam->{name},
        target      => $QoSParam->{target},
        metricId    => $QoSParam->{metricId},
        deviceId    => $QoSParam->{deviceId},
        samplerate  => $QoSParam->{samplerate},
        samplemax   => $QoSParam->{samplemax} || -1
    }, ref($class) || $class)
}

sub setMetricId {
    my ($self, $metricId) = @_;
    $self->{metricId} = $metricId;
    return $self;
}

sub setDeviceId {
    my ($self, $deviceId) = @_;
    $self->{deviceId} = $deviceId;
    return $self;
}

sub sendValue {
    my ($self, $source, $value, $sampletime) = @_;
    my ($RCRobotName, $robotname) = nimGetVarStr(NIMV_ROBOTNAME);
    if($RCRobotName != NIME_OK) {
        print STDERR "throwDefinition() failed to nimGetVarStr NIMV_ROBOTNAME\n";
        nimLog(1, "throwDefinition() failed to nimGetVarStr NIMV_ROBOTNAME");
        return;
    }
    my ($PDS) = src::utils::generateQoS("QOS_MESSAGE", {
        dev_id => $self->{deviceId},
        udata => {
            qos   => $self->{name},
            source => $source,
            target => $self->{target},
            sampletime => $sampletime || time(),
            sampletype => 0,
            samplevalue => $value,
            samplestdev => 0,
            samplerate => $self->{samplerate}
        }
    }, $self->{metricId});
    my ($RCPost) = nimRequest($robotname, 48001, "post_raw", $PDS->data);
    if($RCPost != NIME_OK) {
        my $errorTxt = nimError2Txt($RCPost);
        print STDERR "Failed to post QOS_REACHABILITY QOSDefinition (reason: $errorTxt)\n";
        nimLog(1, "Failed to post QOS_REACHABILITY QOSDefinition (reason: $errorTxt)");
    }
    return $self;
}

sub sendNULL {
    my ($self, $source) = @_;
}

# throw QoSDefinition
sub SendQoSDefinition {
    my ($udata) = @_;
    my ($RCRobotName, $robotname) = nimGetVarStr(NIMV_ROBOTNAME);
    if($RCRobotName != NIME_OK) {
        print STDERR "throwDefinition() failed to nimGetVarStr NIMV_ROBOTNAME\n";
        nimLog(1, "throwDefinition() failed to nimGetVarStr NIMV_ROBOTNAME");
        return;
    }
    my ($PDS) = src::utils::generateQoS("QOS_DEFINITION", {
        udata   => $udata
    });
    my ($RCPost) = nimRequest($robotname, 48001, "post_raw", $PDS->data);
    if($RCPost != NIME_OK) {
        my $errorTxt = nimError2Txt($RCPost);
        print STDERR "Failed to post QOS_REACHABILITY QOSDefinition (reason: $errorTxt)\n";
        nimLog(1, "Failed to post QOS_REACHABILITY QOSDefinition (reason: $errorTxt)");
    }
}

1;