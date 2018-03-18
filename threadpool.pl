my $threadQueue = Thread::Queue->new();
my $threadHandle;
$threadHandle = sub {
    nimLog(3, "Thread started");
    $Logger->info("Thread started!");
    while ( defined ( my $PDSHash = $threadQueue->dequeue() ) ) {
    }
    nimLog(3, "Thread finished");
};

# Wait for group threads
my @thr = map {
    threads->create(\&$threadHandle);
} 1..$STR_NBThreads;
$_->detach() for @thr;