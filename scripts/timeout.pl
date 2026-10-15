#!/usr/bin/perl
# Usage: timeout.pl <seconds> <command...>
# Runs the command in its own process group and kills the whole group when the time is up,
# so a hung test helper (swiftpm-testing-helper) does not survive its swift-test parent.
use strict;
use warnings;
my $limit = shift @ARGV;
my $pid = fork() // die "fork: $!";
if ($pid == 0) {
    setpgrp(0, 0);
    exec @ARGV or die "exec: $!";
}
$SIG{ALRM} = sub {
    print STDERR "timeout.pl: over $limit s, killing: @ARGV\n";
    kill 'KILL', -$pid;
    exit 124;
};
alarm $limit;
waitpid($pid, 0);
exit($? >> 8);
