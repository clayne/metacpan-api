package MetaCPAN::Script::Purge;

use Moose;

use File::Path                ();
use Log::Contextual           qw( :log );
use MetaCPAN::ESConfig        qw( es_doc_path );
use MetaCPAN::Types::TypeTiny qw( Bool HashRef Str );
use MetaCPAN::Util            qw( author_dir true false );

with 'MooseX::Getopt', 'MetaCPAN::Role::Script';

has author => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has release => (
    is       => 'ro',
    isa      => Str,
    required => 0,
);

has force => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has bulk => (
    is      => 'ro',
    isa     => HashRef,
    lazy    => 1,
    builder => '_build_bulk',
);

sub _build_bulk {
    my $self = shift;
    return +{
        map { ; $_ => $self->es->bulk_helper( es_doc_path($_) ) }
            qw(
            author
            contributor
            favorite
            file
            permission
            release
            )
    };
}

has quarantine => (
    is      => 'ro',
    isa     => Str,
    lazy    => 1,
    builder => '_build_quarantine',
);

sub _build_quarantine {
    my $path = "$ENV{HOME}/QUARANTINE";
    if ( !-d $path ) {
        File::Path::mkpath($path);
    }
    return $path;
}

sub _get_scroller_release {
    my ( $self, $query ) = @_;
    return $self->es->scroll_helper(
        scroll => '10m',
        es_doc_path('release'),
        body => {
            query   => $query,
            size    => 500,
            _source => [qw( archive name )],
        },
    );
}

sub _get_scroller_file {
    my ( $self, $query ) = @_;
    return $self->es->scroll_helper(
        scroll => '10m',
        es_doc_path('file'),
        body => {
            query   => $query,
            size    => 500,
            _source => [qw( name )],
        },
    );
}

sub _get_scroller_favorite {
    my ( $self, $query ) = @_;
    return $self->es->scroll_helper(
        scroll => '10m',
        es_doc_path('favorite'),
        body => {
            query   => $query,
            size    => 500,
            _source => false,
        },
    );
}

sub _get_scroller_contributor {
    my ( $self, $query ) = @_;
    return $self->es->scroll_helper(
        scroll => '10m',
        es_doc_path('contributor'),
        body => {
            query   => $query,
            size    => 500,
            _source => [qw( release_name )],
        },
    );
}

sub run {
    my $self = shift;

    if ( $self->author ) {
        if ( !$self->force ) {
            if ( $self->release ) {
                $self->are_you_sure( 'Release '
                        . $self->release
                        . ' by author '
                        . $self->author
                        . ' will be removed from the index !!!' );
            }
            else {
                $self->are_you_sure( 'Author '
                        . $self->author
                        . ' + all their releases will be removed from the index !!!'
                );
            }
        }
        $self->purge_author_releases;
        $self->purge_favorite;
        if ( !$self->release ) {
            $self->purge_author;
            $self->purge_contributor;
        }
    }

    $self->es->indices->refresh;
}

sub purge_author_releases {
    my $self = shift;

    if ( $self->release ) {
        log_info {
            'Looking for release '
                . $self->release
                . ' by author '
                . $self->author
        };

        my $query = {
            bool => {
                must => [
                    { term => { author => $self->author } },
                    { term => { name   => $self->release } }
                ]
            }
        };

        $self->_purge_release($query);
        log_info { 'Finished purging release ' . $self->release };
    }
    else {
        log_info { 'Looking all up author ' . $self->author . ' releases' };
        my $query = { term => { author => $self->author } };
        $self->_purge_release($query);
        log_info { 'Finished purging releases for author ' . $self->author };
    }
}

sub _purge_release {
    my ( $self, $query ) = @_;

    my $scroll = $self->_get_scroller_release($query);
    my @remove_ids;
    my @remove_release_files;
    my @remove_release_archives;

    while ( my $r = $scroll->next ) {
        log_debug { 'Removing release ' . $r->{_source}{name} };
        push @remove_ids,              $r->{_id};
        push @remove_release_files,    $r->{_source}{name};
        push @remove_release_archives, $r->{_source}{archive};
    }

    if (@remove_ids) {
        $self->bulk->{release}->delete_ids(@remove_ids);
        $self->bulk->{release}->flush;
    }

    for my $release (@remove_release_files) {
        $self->_purge_files($release);
    }

    # remove the release archive
    for my $archive (@remove_release_archives) {
        log_info { "Moving archive $archive to " . $self->quarantine };
        $self->cpan->file( 'authors', author_dir( $self->author ), $archive )
            ->move_to( $self->quarantine );
    }
}

sub _purge_files {
    my ( $self, $release ) = @_;
    log_info {
        'Looking for files of release '
            . $release
            . ' by author '
            . $self->author
    };

    my $query = {
        bool => {
            must => [
                { term => { author  => $self->author } },
                { term => { release => $release } }
            ]
        }
    };

    my $scroll = $self->_get_scroller_file($query);
    my @remove;

    while ( my $f = $scroll->next ) {
        log_debug {
            'Removing file ' . $f->{_source}{name} . ' of release ' . $release
        };
        push @remove, $f->{_id};
    }

    if (@remove) {
        $self->bulk->{file}->delete_ids(@remove);
        $self->bulk->{file}->flush;
    }

    log_info { 'Finished purging files for release ' . $release };
}

sub purge_favorite {
    my ( $self, $release ) = @_;

    if ( $self->release ) {
        log_info {
            'Looking for favorites of release '
                . $self->release
                . ' by author '
                . $self->author
        };
        $self->_purge_favorite( { term => { release => $self->release } } );
        log_info {
            'Finished purging favorites for release ' . $self->release
        };
    }
    else {
        log_info { 'Looking for favorites author ' . $self->author };
        $self->_purge_favorite( { term => { author => $self->author } } );
        log_info { 'Finished purging favorites for author ' . $self->author };
    }
}

sub _purge_favorite {
    my ( $self, $query ) = @_;

    my $scroll = $self->_get_scroller_favorite($query);
    my @remove;

    while ( my $f = $scroll->next ) {
        push @remove, $f->{_id};
    }

    if (@remove) {
        $self->bulk->{favorite}->delete_ids(@remove);
        $self->bulk->{favorite}->flush;
    }
}

sub purge_author {
    my $self = shift;
    log_info { 'Purging author ' . $self->author };

    $self->bulk->{author}->delete_ids( $self->author );
    $self->bulk->{author}->flush;

    log_info { 'Finished purging author ' . $self->author };
}

sub purge_contributor {
    my $self = shift;
    log_info { 'Looking all up author ' . $self->author . ' contributions' };

    my @remove;

    my $query_release_author
        = { term => { release_author => $self->author } };

    my $scroll_release_author
        = $self->_get_scroller_contributor($query_release_author);

    while ( my $r = $scroll_release_author->next ) {
        log_debug {
            'Removing contributions to releases by author ' . $self->author
        };
        push @remove, $r->{_id};
    }

    my $query_pauseid = { term => { pauseid => $self->author } };

    my $scroll_pauseid = $self->_get_scroller_contributor($query_pauseid);

    while ( my $c = $scroll_pauseid->next ) {
        log_debug { 'Removing contributions of author ' . $self->author };
        push @remove, $c->{_id};
    }

    if (@remove) {
        $self->bulk->{contributor}->delete_ids(@remove);
        $self->bulk->{contributor}->flush;
    }

    log_info {
        'Finished purging contribution entries related to ' . $self->author
    };
}

__PACKAGE__->meta->make_immutable;
1;

=pod

=head1 SYNOPSIS

Purge releases from the index, by author or name

  $ bin/metacpan purge --author X
  $ bin/metacpan purge --release Y

=cut
