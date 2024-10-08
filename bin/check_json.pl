#!/usr/bin/env perl
# PODNAME: check_json.pl
use 5.010;

use Data::Dumper     qw( Dumper );
use Cpanel::JSON::XS qw( decode_json );

foreach my $file (@ARGV) {
    say "Processing $file";
    eval {
        my $hash = decode_json(
            do { local ( @ARGV, $/ ) = $file; <> }
        );
        print Dumper($hash);
    };

    if ($@) { say "\terror in $file: $@" }
}
