use strict;
use warnings;
use lib 't/lib';

use MetaCPAN::Model::Release ();
use MetaCPAN::TestHelpers    qw( fakecpan_dir get_config );
use Test::Deep               qw( cmp_bag );
use Test::More;

my $config = get_config();

subtest 'basic dependencies' => sub {
    my $file
        = fakecpan_dir->child(
        '/authors/id/M/MS/MSCHWERN/Prereqs-Basic-0.01.tar.gz');

    my $release = MetaCPAN::Model::Release->new( file => $file );

    my $dependencies = $release->dependencies;

    cmp_bag $dependencies,
        [
        {
            phase        => 'build',
            relationship => 'requires',
            module       => 'For::Build::Requires1',
            version      => 2.45
        },
        {
            phase        => 'configure',
            relationship => 'requires',
            module       => 'For::Configure::Requires1',
            version      => 72
        },
        {
            phase        => 'runtime',
            relationship => 'requires',
            module       => 'For::Runtime::Requires1',
            version      => 0
        },
        {
            phase        => 'runtime',
            relationship => 'requires',
            module       => 'For::Runtime::Requires2',
            version      => 1.23
        },
        {
            phase        => 'runtime',
            relationship => 'recommends',
            module       => 'For::Runtime::Recommends1',
            version      => 0
        }
        ];
};

done_testing;
