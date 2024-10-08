use strict;
use warnings;
use lib 't/lib';

use MetaCPAN::TestHelpers qw( test_release );
use MetaCPAN::Util        qw(true false);
use Test::More;

test_release( {
    name         => 'Devel-GoFaster-0.000',
    distribution => 'Devel-GoFaster',
    author       => 'LOCAL',
    authorized   => true,
    first        => true,
    version      => '0.000',

    provides => [ 'Devel::GoFaster', ],

    # Don't test the actual numbers since we copy this out of the real
    # database as a live test case.
    tests => 1,
} );

done_testing;
