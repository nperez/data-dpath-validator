package Data::DPath::Validator;

#ABSTRACT: Validate data based on template data

use Moose;
use Data::DPath 'dpath';
use Data::DPath::Validator::Visitor;
use namespace::autoclean;

=head1 SYNOPSIS

    use strict;
    use warnings;
    use Data::DPath::Validator;

    my $template = { foo => '*' };
    my $data = [{ foo => [1,2,3] }, { foo => { bar => 'mtfnpy' } } ];

    my $v = Data::DPath::Validator->new();
    $v->load($template);

    my $ret = $v->validate(@$data);

    if($ret->[0] && $ret->[1])
    {
        print "Hooray!\n";
    }

=cut

with 'MooseX::Role::BuildInstanceOf' =>
{
    target => 'Data::DPath::Validator::Visitor',
    prefix => 'visitor'
};

=attr visitor

This contains our Data::DPath::Validator::Visitor instance constructed via 
MooseX::Role::BuildInstanceOf.

It handles the following methods:

=over 4

=item load -> visit

load() takes any number of data structures and visit()s via Data::Visitor to
generate Data::DPath paths, storing a different path for each "branch" in each
data structure. 

=item templates

templates() is the accessor from the Visitor to return an ArrayRef[Str]
containing all of the parsed templates.

=back

=cut

has '+visitor' =>
(
    handles =>
    {
        'load' => 'visit',
        'templates' => 'templates'
    }
);

=attr strict_mode is: ro, isa: Bool, default: 0

strict_mode determines how strict the validation is. By default, only a single
template path needs to match for the data structure to be okay. With
strict_mode on, all paths must pass on the supplied data or it fails

=cut

has 'strict_mode' =>
(
    is => 'ro',
    isa => 'Bool',
    default => 0,
);

=method validate

Validate takes any number of data structures and verifies that each matches at
least one of the DPaths generated from the template data structures.

Returns ArrayRef[Bool] which each indice corresponding to order in which the 
data was supplied.

=cut

sub validate
{
    my $self = shift;
    
    my $ret = [];
    foreach my $data (@_)
    {
        my $pass = $self->strict_mode
            ? $self->_strict_validation($data)
            : $self->_loose_validation($data);
        
        push(@$ret, $pass);
    }

    return $ret;
}

sub _strict_validation
{
    my ($self, $data) = @_;
    
    foreach my $template (@{$self->templates})
    {
        if(!dpath($template)->match($data))
        {
            return 0;
        }
    }

    return 1;
}

sub _loose_validation
{
    my ($self, $data) = @_;
    
    foreach my $template (@{$self->templates})
    {
        if(dpath($template)->match($data))
        {
            return 1;
        }
    }

    return 0;
}

__PACKAGE__->meta->make_immutable();
1;

__END__

=head1 DESCRIPTION

Data::DPath::Validator is a simple data validator using normal Perl data
structures as templates. It accomplishes this by translating your template into
a series Data::DPath paths (one for each "branch") using Data::Visitor to
traverse the data structure like a SAX parser. Then when calling validate(),
each path is then attempted against the supplied data.

=head1 NOTES

A template is defined by using a normal Perl data structure like in the
synopsis, with the parts where 'any' data is acceptable being replaced with an
asterisk ('*').

By default, the validator is in loose validation mode, meaning as long as one
path matches, the data structure passes. To instead require strict validation
do this:

    my $v = Data::DPath::Validator->new(strict_mode => 1);
