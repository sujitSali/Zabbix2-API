package Zabbix2::API::UserGroup;

use strict;
use warnings;
use 5.010;
use Carp;
use autodie;
use utf8;

use Moo;
extends qw/Zabbix2::API::CRUDE/;

use Zabbix2::API::User;

has 'users' => (is => 'ro',
                lazy => 1,
                builder => '_fetch_users');

sub id {
    ## mutator for id
    my ($self, $value) = @_;
    if (defined $value) {
        $self->data->{usrgrpid} = $value;
        return $self->data->{usrgrpid};
    } else {
        return $self->data->{usrgrpid};
    }
}

sub _prefix {
    my (undef, $suffix) = @_;
    if ($suffix and $suffix =~ m/ids?/) {
        return 'usrgrp'.$suffix;
    } elsif ($suffix) {
        return 'usergroup'.$suffix;
    } else {
        return 'usergroup';
    }
}

sub _extension {
    return (output => 'extend');
}

sub name {
    my $self = shift;
    return $self->data->{name} || '???';
}

sub _fetch_users {
    my $self = shift;
    my $users = $self->{root}->fetch('User', params => { usrgrpids => [ $self->id ] });
    return $users;
}

1;
__END__
=pod

=head1 NAME

Zabbix2::API::UserGroup -- Zabbix usergroup objects

=head1 SYNOPSIS

  use Zabbix2::API::UserGroup;

  my $group = $zabbix->fetch(...);

  $group->delete;

=head1 DESCRIPTION

Handles CRUD for Zabbix usergroup objects.

This is a very simple subclass of C<Zabbix2::API::CRUDE>.  Only the
required methods are implemented (and in a very simple fashion on top
of that).

=head1 METHODS

=over 4

=item name()

Accessor for the usergroup's name (the "name" attribute); returns the
empty string if no name is set, for instance if the usergroup has not
been created on the server yet.

=item users()

Mutator for the usergroup's users.

=item push()

This method handles extraneous C<< user => Zabbix2::API::User >>
attributes in the users array, transforming them into C<userid>
attributes, and pushing the users to the server if they don't exist
already.  The original user attributes are kept but hidden from the
C<CRUDE> C<push> method, and restored after the C<pull> method is
called.

This means you can put C<Zabbix2::API::User> objects in your data and
the module will Do The Right Thing (assuming you agree with my
definition of the Right Thing).  Users that have been created this way
will not be removed from the server if they are removed from the
graph, however.

Overridden from C<Zabbix2::API::CRUDE>.

=back

=head1 SEE ALSO

L<Zabbix2::API::CRUDE>.

=head1 AUTHOR

Fabrice Gabolde <fga@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 SFR

This library is free software; you can redistribute it and/or modify it under
the terms of the GPLv3.

=cut
