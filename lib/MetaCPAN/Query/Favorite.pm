package MetaCPAN::Query::Favorite;

use MetaCPAN::Moose;

use MetaCPAN::ESConfig qw( es_doc_path );
use MetaCPAN::Util     qw( MAX_RESULT_WINDOW hit_total );

with 'MetaCPAN::Query::Role::Common';

sub agg_by_distributions {
    my ( $self, $distributions, $user ) = @_;
    return {
        favorites   => {},
        myfavorites => {},
        took        => 0,
        }
        unless $distributions;

    my $body = {
        size  => 0,
        query => {
            terms => { distribution => $distributions }
        },
        aggregations => {
            favorites => {
                terms => {
                    field => 'distribution',
                    size  => scalar @{$distributions},
                },
            },
            $user
            ? (
                myfavorites => {
                    filter       => { term => { user => $user } },
                    aggregations => {
                        entries => {
                            terms => { field => 'distribution' }
                        }
                    }
                }
                )
            : (),
        }
    };

    my $ret = $self->es->search( es_doc_path('favorite'), body => $body, );

    my %favorites = map { $_->{key} => $_->{doc_count} }
        @{ $ret->{aggregations}{favorites}{buckets} };

    my %myfavorites;
    if ($user) {
        %myfavorites = map { $_->{key} => $_->{doc_count} }
            @{ $ret->{aggregations}{myfavorites}{entries}{buckets} };
    }

    return {
        favorites   => \%favorites,
        myfavorites => \%myfavorites,
        took        => $ret->{took},
    };
}

sub by_user {
    my ( $self, $user, $size ) = @_;
    $size ||= 250;

    my $favs = $self->es->search(
        es_doc_path('favorite'),
        body => {
            query   => { term => { user => $user } },
            _source => [qw( author date distribution )],
            sort    => ['distribution'],
            size    => $size,
        }
    );
    return {} unless hit_total($favs);
    my $took = $favs->{took};

    my @favs = map { $_->{_source} } @{ $favs->{hits}{hits} };

    # filter out backpan only distributions

    my $no_backpan = $self->es->search(
        es_doc_path('release'),
        body => {
            query => {
                bool => {
                    must => [
                        { terms => { status => [qw( cpan latest )] } },
                        {
                            terms => {
                                distribution =>
                                    [ map { $_->{distribution} } @favs ]
                            }
                        },
                    ]
                }
            },
            _source => ['distribution'],
            size    => scalar(@favs),
        }
    );
    $took += $no_backpan->{took};

    if ( hit_total($no_backpan) ) {
        my %has_no_backpan = map { $_->{_source}{distribution} => 1 }
            @{ $no_backpan->{hits}{hits} };

        @favs = grep { exists $has_no_backpan{ $_->{distribution} } } @favs;
    }

    return { favorites => \@favs, took => $took };
}

sub leaderboard {
    my $self = shift;

    my $body = {
        size         => 0,
        query        => { match_all => {} },
        aggregations => {
            leaderboard => {
                terms => {
                    field => 'distribution',
                    size  => 100,
                },
            },
            totals => {
                cardinality => {
                    field => 'distribution',
                },
            },
        },
    };

    my $ret = $self->es->search( es_doc_path('favorite'), body => $body, );

    return {
        leaderboard => $ret->{aggregations}{leaderboard}{buckets},
        total       => $ret->{aggregations}{totals}{value},
        took        => $ret->{took},
    };
}

sub recent {
    my ( $self, $page, $size ) = @_;
    $page //= 1;
    $size //= 100;

    if ( $page * $size >= MAX_RESULT_WINDOW ) {
        return +{
            favorites => [],
            took      => 0,
            total     => 0,
        };
    }

    my $favs = $self->es->search(
        es_doc_path('favorite'),
        body => {
            size  => $size,
            from  => ( $page - 1 ) * $size,
            query => { match_all => {} },
            sort  => [ { 'date' => { order => 'desc' } } ]
        }
    );

    my @favs = map { $_->{_source} } @{ $favs->{hits}{hits} };

    return +{
        favorites => \@favs,
        took      => $favs->{took},
        total     => hit_total($favs),
    };
}

sub users_by_distribution {
    my ( $self, $distribution ) = @_;

    my $favs = $self->es->search(
        es_doc_path('favorite'),
        body => {
            query   => { term => { distribution => $distribution } },
            _source => ['user'],
            size    => 1000,
        }
    );
    return {} unless hit_total($favs);

    my @plusser_users = map { $_->{_source}{user} } @{ $favs->{hits}{hits} };

    return { users => \@plusser_users };
}

__PACKAGE__->meta->make_immutable;
1;
