package MetaCPAN::Tests::Distribution;
use Test::More;
use Test::Routine;
use version;
use MetaCPAN::Types::TypeTiny qw( Str );

with qw( MetaCPAN::Tests::Query );

sub _build_type {'distribution'}

sub _build_search {
    my $self = shift;
    return { term => { name => $self->name } };
}

my @attrs = qw(
    name
);

has [@attrs] => (
    is  => 'ro',
    isa => Str,
);

test 'distribution attributes' => sub {
    my ($self) = @_;

    foreach my $attr (@attrs) {
        is $self->data->{$attr}, $self->$attr, $attr;
    }
};

1;
