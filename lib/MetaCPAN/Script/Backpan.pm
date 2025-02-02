package MetaCPAN::Script::Backpan;

use strict;
use warnings;

use Moose;

use Log::Contextual           qw( :log :dlog );
use MetaCPAN::ESConfig        qw( es_doc_path );
use MetaCPAN::Types::TypeTiny qw( Bool HashRef Str );

with 'MetaCPAN::Role::Script', 'MooseX::Getopt::Dashes';

has distribution => (
    is            => 'ro',
    isa           => Str,
    documentation => 'work on given distribution',
);

has undo => (
    is            => 'ro',
    isa           => Bool,
    default       => 0,
    documentation => 'mark releases as status=cpan',
);

has files_only => (
    is            => 'ro',
    isa           => Bool,
    default       => 0,
    documentation => 'only update the "file" index',
);

has _release_status => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { +{} },
);

has _bulk => (
    is      => 'ro',
    isa     => HashRef,
    default => sub { +{} },
);

sub run {
    my $self = shift;

    $self->es->trace_calls(1) if $ENV{DEBUG};

    $self->build_release_status_map();

    $self->update_releases() unless $self->files_only;

    $self->update_files();

    $_->flush for values %{ $self->_bulk };
}

sub build_release_status_map {
    my $self = shift;

    log_info {"find_releases"};

    my $scroll = $self->es->scroll_helper(
        scroll => '5m',
        es_doc_path('release'),
        body => {
            %{ $self->_get_release_query },
            size    => 500,
            _source => [ 'author', 'archive', 'name' ],
        },
    );

    while ( my $release = $scroll->next ) {
        my $author  = $release->{_source}{author};
        my $archive = $release->{_source}{archive};
        my $name    = $release->{_source}{name};
        next unless $name;    # bypass some broken releases

        $self->_release_status->{$author}{$name} = [
            (
                $self->undo
                    or exists $self->cpan_file_map->{$author}{$archive}
                )
            ? 'cpan'
            : 'backpan',
            $release->{_id}
        ];
    }
}

sub _get_release_query {
    my $self = shift;

    unless ( $self->undo ) {
        return +{
            query => {
                bool =>
                    { must_not => [ { term => { status => 'backpan' } } ] }
            }
        };
    }

    return +{
        query => {
            bool => {
                must => [
                    { term => { status => 'backpan' } },
                    (
                        $self->distribution
                        ? {
                            term => { distribution => $self->distribution }
                            }
                        : ()
                    )
                ]
            }
        }
    };
}

sub update_releases {
    my $self = shift;

    log_info {"update_releases"};

    $self->_bulk->{release} ||= $self->es->bulk_helper(
        es_doc_path('release'),
        max_count => 250,
        timeout   => '5m',
    );

    for my $author ( keys %{ $self->_release_status } ) {

        # value = [ status, _id ]
        for ( values %{ $self->_release_status->{$author} } ) {
            $self->_bulk->{release}->update( {
                id  => $_->[1],
                doc => {
                    status => $_->[0],
                }
            } );
        }
    }
}

sub update_files {
    my $self = shift;

    for my $author ( keys %{ $self->_release_status } ) {
        my @releases = keys %{ $self->_release_status->{$author} };
        while ( my @chunk = splice @releases, 0, 1000 ) {
            $self->update_files_author( $author, \@chunk );
        }
    }
}

sub update_files_author {
    my $self            = shift;
    my $author          = shift;
    my $author_releases = shift;

    log_info { "update_files: " . $author };

    my $scroll = $self->es->scroll_helper(
        scroll => '5m',
        es_doc_path('file'),
        body => {
            query => {
                bool => {
                    must => [
                        { term  => { author  => $author } },
                        { terms => { release => $author_releases } }
                    ]
                }
            },
            size    => 500,
            _source => ['release'],
        },
    );

    $self->_bulk->{file} ||= $self->es->bulk_helper(
        es_doc_path('file'),
        max_count => 250,
        timeout   => '5m',
    );
    my $bulk = $self->_bulk->{file};

    while ( my $file = $scroll->next ) {
        my $release = $file->{_source}{release};
        $bulk->update( {
            id  => $file->{_id},
            doc => {
                status => $self->_release_status->{$author}{$release}[0]
            }
        } );
    }
}

__PACKAGE__->meta->make_immutable;
1;

=pod

Sets "backpan" status on all BackPAN releases.

=cut
