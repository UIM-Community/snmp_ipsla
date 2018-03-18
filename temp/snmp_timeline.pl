
use strict;
use threads;
use Thread::Queue;
use threads::shared;
use POSIX;

my $total_t = 30000;
my $total_e: shared = 350;
my $poll_interval: shared = floor($total_t / $total_e) / 1000;

print "Poll interval => $poll_interval ms\n";

my $handle : shared = Thread::Queue->new();
my $start = time();
my $timeline = threads->create(sub {
    my $i = $total_e;
    while($i > 0) {
        $handle->enqueue($i);
        $i--;
        select(undef, undef, undef, $poll_interval);
    }
    $handle->enqueue(undef);
});

my $pullThread = threads->create(sub {
    print "pull thread started!\n";
    while ( defined(my $i = $handle->dequeue()) ) {
        print "$i\n";
    }
    print "pull thread finished!\n";
});

my @threads = ($pullThread, $timeline);
$_->join() for @threads; 

my $execution_time = sprintf("%.2f", time() - $start);
print "$execution_time\n";

