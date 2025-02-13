use strict;
use warnings;
use lib 't/lib';

use MetaCPAN::Server::Test qw( app GET test_psgi );
use MetaCPAN::TestHelpers  qw( decode_json_ok );
use Test::More;

test_psgi app, sub {
    my $cb = shift;

    # test ES script using doc['blah'] value
    {
        ok( my $res = $cb->( GET '/search/autocomplete?q=Multiple::Modu' ),
            'GET' );
        my $json = decode_json_ok($res);

        my $got = [ map { $_->{fields}{documentation} }
                @{ $json->{hits}{hits} } ];

        is_deeply $got, [ qw(
            Multiple::Modules
            Multiple::Modules::A
            Multiple::Modules::B
            Multiple::Modules::RDeps
            Multiple::Modules::Tester
            Multiple::Modules::RDeps::A
            Multiple::Modules::RDeps::Deprecated
        ) ],
            'results are sorted lexically by module name + length'
            or diag( Test::More::explain($got) );
    }
};

test_psgi app, sub {
    my $cb = shift;

    # test ES script using doc['blah'] value
    {
        ok(
            my $res
                = $cb->(
                GET '/search/autocomplete/suggest?q=Multiple::Modu' ),
            'GET'
        );
        my $json = decode_json_ok($res);

        my $got = [ map $_->{name}, @{ $json->{suggestions} } ];

        is_deeply $got, [ qw(
            Multiple::Modules
            Multiple::Modules::A
            Multiple::Modules::B
            Multiple::Modules::RDeps
            Multiple::Modules::Tester
            Multiple::Modules::RDeps::A
            Multiple::Modules::RDeps::Deprecated
        ) ],
            'results are sorted lexically by module name + length'
            or diag( Test::More::explain($got) );
    }
};

done_testing;
