package Zabbix2::API::User;

use strict;
use warnings;
use 5.010;
use Carp;
use autodie;
use utf8;

use Moo;
extends qw/Exporter Zabbix2::API::CRUDE/;

use constant {
    USER_TYPE_USER => 1,
    USER_TYPE_ADMIN => 2,
    USER_TYPE_SUPERADMIN => 3,
};

our @EXPORT_OK = qw/
USER_TYPE_USER
USER_TYPE_ADMIN
USER_TYPE_SUPERADMIN/;

our %EXPORT_TAGS = (
    user_types => [
        qw/USER_TYPE_USER
        USER_TYPE_ADMIN
        USER_TYPE_SUPERADMIN/
    ],
    );

sub _readonly_properties {
    return {
        userid => 1,
        attempt_clock => 1,
        attempt_failed => 1,
        attempt_ip => 1,
    };
}

sub id {
    ## mutator for id
    my ($self, $value) = @_;
    if (defined $value) {
        $self->data->{userid} = $value;
        return $self->data->{userid};
    } else {
        return $self->data->{userid};
    }
}

sub _prefix {
    my (undef, $suffix) = @_;
    if ($suffix) {
        return 'user'.$suffix;
    } else {
        return 'user';
    }
}

sub _extension {
    return (output => 'extend');
}

sub name {
    my $self = shift;
    return $self->data->{alias} || '???';
}

sub _usergroup_or_name_to_usergroup {

    my $zabbix = shift;
    my $usergroup_or_name = shift;
    my $usergroup;

    if (ref $usergroup_or_name and eval { $usergroup_or_name->isa('Zabbix2::API::UserGroup') }) {

        # it's a UserGroup object, keep it
        $usergroup = $usergroup_or_name;

    } elsif (not ref $usergroup_or_name) {

        $usergroup = $zabbix->fetch_single('UserGroup', params => { filter => { name => $usergroup_or_name } });

        unless ($usergroup) {

            die 'Parameter to add_to_usergroup or set_usergroups must be a Zabbix2::API::UserGroup object or an existing usergroup name';

        }

    } else {

        die 'Parameter to add_to_usergroup or set_usergroups must be a Zabbix2::API::UserGroup object or an existing usergroup name';

    }

    return $usergroup;

}

sub add_to_usergroup {

    my ($self, $usergroup_or_name) = @_;
    my $usergroup = _usergroup_or_name_to_usergroup($self->{root}, $usergroup_or_name);

    croak('Cannot add user without ID to usergroup: needs to be created or fetched')
        unless $self->id;

    $self->{root}->query(method => 'usergroup.massAdd',
                         params => { usrgrpids => [ $usergroup->id ],
                                     userids => [ $self->id ] });

    return $self;

}

sub set_usergroups {

    my ($self, @list_of_usergroups_or_names) = @_;

    die 'User does not exist (yet?) on server'
        unless $self->created;

    my @list_of_usergroups = map { _usergroup_or_name_to_usergroup($self->{root}, $_) } @list_of_usergroups_or_names;

    $self->{root}->query(method => 'user.update',
                         params => { userid => $self->id,
                                     usrgrps => [ map { $_->id } @list_of_usergroups ] });

    return $self;

}

sub set_password {

    my ($self, $password) = @_;
    $self->data->{passwd} = $password;
    return $self;

}

1;
__END__
=pod

=head1 NAME

Zabbix2::API::User -- Zabbix user objects

=head1 SYNOPSIS

  use Zabbix2::API::User;
  # fetch a single user by login ("alias")
  my $user = $zabbix->fetch('User', params => { filter => { alias => 'luser' } })->[0];
  
  # and delete it
  $user->delete;

=head1 DESCRIPTION

Handles CRUD for Zabbix user objects.

This is a subclass of C<Zabbix2::API::CRUDE>; see there for inherited methods.

=head1 METHODS

=over 4

=item usergroups()

Returns an arrayref of the user's usergroups (possibly empty) as
L<Zabbix2::API::UserGroup> objects.

=item add_to_usergroup(USERGROUP_OR_NAME)

Takes a L<Zabbix2::API::UserGroup> instance or a valid usergroup name,
and adds the current user to the group.  Returns C<$self>.

=item set_usergroups(LIST_OF_USERGROUPS_OR_NAMES)

Takes a list of L<Zabbix2::API::UserGroup> instances or valid usergroup
names, and sets the user/usergroup relationship appropriately.
Returns C<$self>.

=item set_password(NEW_PASSWORD)

Sets the user's password.  The modified user is not pushed
automatically to the server.

=item name()

Accessor for the user's name (the "alias" attribute).

=item collides()

This method returns a list of users colliding (i.e. matching) this
one. If there if more than one colliding user found the implementation
can not know on which one to perform updates and will bail out.

=back

=head1 EXPORTS

User types are implemented as constants:

  USER_TYPE_USER
  USER_TYPE_ADMIN
  USER_TYPE_SUPERADMIN

Promote (or demote) users by setting their C<$user->data->{type}>
attribute to one of these.

Nothing is exported by default; you can use the tag C<:user_types> (or
import by name).

=head1 BUGS AND ODDITIES

Apparently when logging in via the web page Zabbix does not care about
the case of your username (e.g. "admin", "Admin" and "ADMIN" will all
work).  I have not tested this for filtering/searching/colliding
users.

=head2 WHERE'S THE remove_from_usergroup METHOD?

L<This|https://support.zabbix.com/browse/ZBX-6124> is where it is.

=head1 SEE ALSO

L<Zabbix2::API::CRUDE>.

=head1 AUTHOR

Fabrice Gabolde <fga@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2013 SFR

This library is free software; you can redistribute it and/or modify it under
the terms of the GPLv3.

=cut
