package Data::DPath::Validator::Visitor;

#ABSTRACT: Data::Visitor subclass for generating DPaths


=head1 SYNOPSIS

    use Data::DPath::Validator::Visitor;
    my $v = Data::DPath::Validator::Visitor->new();
    $v->visit({foo => '*'});

    $v->templates; # [ '/foo/*' ]

=cut

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::Types::Moose(':all');
use Scalar::Util;
use namespace::autoclean;

extends 'Data::Visitor';

use constant DEBUG => $ENV{DATA_DPATH_VALIDATOR_DEBUG};

=attr templates is: ro, isa: ArrayRef[Str], traits: Array

templates contains the parsed paths from calling visit on template data

    handles =>
    {
        add_template => 'push'
    }

=cut

has 'templates' =>
(
    is => 'ro',
    isa => ArrayRef[Str],
    traits => ['Array'],
    default => sub { [ ] },
    handles =>
    {
        add_template => 'push',
    },
);

=attr current_template is: ro, isa: Str, default: '', traits: String

current_template holds the template as it is being build prior to being added
to the templates attribute

    handles =>
    {
        append_text => 'append',
        prepend_text => 'prepend',
        reset_template => 'clear',
    }

=cut

has 'current_template' =>
(
    is => 'ro',
    isa => Str,
    default => '',
    traits => ['String'],
    handles =>
    {
        append_text => 'append',
        prepend_text => 'prepend',
        reset_template => 'clear',
    }
);

=attr template_stack is: ro, isa: ArrayRef[Str], default: [], traits: Array

template_stack maintains the templates as we branch down the data structure. At
each level down, the current template is pushed onto the stack and popped off
when the that branch bottom is reached. 

    handles =>
    {
        push_template => 'push',
        pop_template => 'pop',
    },

=cut

has 'template_stack' =>
(
    is => 'ro',
    isa => ArrayRef[Str],
    default => sub { [ ] },
    traits => ['Array'],
    handles =>
    {
        push_template => 'push',
        pop_template => 'pop',
    },
);

=attr structure_depth is: ro, isa: Int, default: 0, traits: Counter

structure_depth keeps track of how deep we are in the data structure.

    handles =>
    {
        lower => 'inc',
        higher => 'dec',
    },

=cut

has 'structure_depth' =>
(
    is => 'ro',
    isa => Int,
    traits => ['Counter'],
    default => 0,
    handles =>
    {
        lower => 'inc',
        higher => 'dec',
    },
);


=attr value_type is: rw, isa: enum ArrayElem HashVal HashKey NONE, default:NONE

value_type keeps track of what kind of element we are viewing inside
visit_value. This attribute is important for determining path construction.


=cut

has 'value_type' =>
(
    is => 'rw',
    isa => enum([qw/ArrayElem HashVal HashKey NONE/]),
    default => 'NONE'
);


=method dive

dive() increases our depth into the data structure, pushing the current
template onto the template stack.

=cut

sub dive
{
    my $self = shift;

    warn 'DIVE: '. $self->current_template if DEBUG;
    $self->push_template($self->current_template);
    $self->lower();
}


=method rise

rise() decreases our depth from the data structure, popping a template from the
template stack and replacing the current_template with it.

=cut

sub rise
{
    my $self = shift;

    warn 'PRE-RISE: '. $self->current_template if DEBUG;
    my $template = $self->pop_template();
    $self->reset_template();
    $self->append_text($template);
    $self->higher();
    warn 'POST-RISE: '. $self->current_template if DEBUG;
}

=method visit_value

visit_value is overriden to provide the meat of the DPath generation algorithm.
It reads $self->value_type to know how append to the current_template.

=cut

sub visit_value
{
    my ($self, $val) = @_;
    warn 'VISIT: '. $self->current_template if DEBUG;
    
    if($self->value_type eq 'ArrayElem')
    {
        if($val eq '*')
        {
            $self->append_text("/$val");
            $self->add_template($self->current_template);
            return;
        }
        $self->append_text('/.[ value ');
    }
    elsif($self->value_type eq 'HashVal')
    {
        if($val eq '*')
        {
            $self->append_text("/$val");
            $self->add_template($self->current_template);
            return;
        }
        $self->append_text('/*[ value ');
    }
    elsif($self->value_type eq 'HashKey')
    {
        $self->append_text($val);
        $self->add_template($self->current_template);
        return;
    }
    else
    {
        $self->append_text('.[ value ');
    }

    if(Scalar::Util::looks_like_number($val))
    {
        $self->append_text("== $val");
    }
    else
    {
        $self->append_text("eq '$val'");
    }

    $self->append_text(']');
    $self->add_template($self->current_template);
}

=method around visit_hash

visit_hash is advised to adjust our depth and prep our current template.

After calling the original method, depth is adjusted back.

=cut

around visit_hash => sub
{
    my ($orig, $self, $hash) = @_;
    $self->dive();
    $self->append_text('/') if $self->structure_depth > 1;
    warn 'HASH: '. $self->current_template if DEBUG;
    $self->$orig($hash);
    $self->rise();
};

=method around visit_hash_key

visit_hash_key is advised to set value_type to HashKey prior to calling the
original method

=cut

around visit_hash_key => sub
{
    my ($orig, $self, $key) = @_;
    $self->value_type('HashKey');
    warn 'HASHKEY: '. $self->current_template if DEBUG;
    $self->$orig($key);
    $self->value_type('NONE');
};

=method around visit_hash_value

visit_hash_value is advised to set value_type to HashVal prior to calling the
original method

=cut

around visit_hash_value => sub
{
    my ($orig, $self, $val) = @_;
    $self->value_type('HashVal');
    warn 'HASHVAL: '. $self->current_template if DEBUG;
    $self->$orig($val);
    $self->value_type('NONE');
};

=method around visit_hash_entry

visit_hash_entry is advised to adjust out depth prior to evaluating the key and
value.

After calling the original method, depth is adjusted back.

=cut

around visit_hash_entry => sub
{
    my ($orig, $self, $key, $value, $hash) = @_;
    $self->dive();
    warn 'HASHENTRY: '. $self->current_template if DEBUG;
    $self->$orig($key, $value, $hash);
    $self->rise();
};

=method around visit_array

visit_array is advised to adjust our depth and prep our current template.

After calling the original method, depth is adjusted back.

=cut

around visit_array => sub
{
    my ($orig, $self, $array) = @_;
    $self->dive();
    $self->append_text('/') if $self->structure_depth > 1;
    warn 'ARRAY: '. $self->current_template if DEBUG;
    $self->$orig($array);
    $self->rise();
};

=method around visit_array_entry

visit_array_entry is advised to set the value_type to ArrayElem and to also
prep the current template with the array index before calling the original.

After calling the original method, depth is adjusted back.

=cut

around visit_array_entry => sub
{
    my ($orig, $self, $elem, $index, $array) = @_;
    $self->dive();
    $self->value_type('ArrayElem');
    $self->append_text("*[ idx == $index ]");
    warn 'ARRAYENTRY: '. $self->current_template if DEBUG;
    $self->$orig($elem, $index, $array);
    $self->rise();
    $self->value_type('NONE');
};

=method around visit

visit is advised to prep the initial template if the structure depth is zero
before calling the original. Afterward, if the depth has resolved back to zero,
the current template is reset.

=cut

around visit => sub
{
    my ($orig, $self) = (shift, shift);
    
    if($self->structure_depth == 0)
    {
        $self->append_text('/');
    }
    my @ret = $self->$orig(@_);
    
    $self->reset_template() if $self->structure_depth == 0;

    defined wantarray ? @ret : $ret[0];

};

__PACKAGE__->meta->make_immutable();
1;

__END__

=head1 DESCRIPTION

Data::DPath::Validator::Visitor subclasses Data::Visitor to parse arbitrary
Perl data structures into Data::DPath paths. It stores these paths in its
templates attribute.

