package Zabbix2::API;

use strict;
use warnings;
use 5.010;
use Carp;

use Moo;

use Scalar::Util qw/blessed/;
use Module::Loaded;
use Module::Load;
use Params::Validate qw/validate :types/;
use JSON;
use LWP::UserAgent;
use Log::Any;

our $VERSION = '0.014';

has 'server' => (is => 'ro',
                 required => 1);
has 'ua' => (is => 'ro',
             lazy => 1,
             builder => '_build_ua');
has 'cookie' => (is => 'ro',
                 predicate => 1,
                 clearer => '_clear_cookie',
                 writer => '_set_cookie');
has 'user' => (is => 'ro',
               init_arg => undef,
               clearer => '_clear_user',
               writer => '_set_user');
# equivalent to the old "lazy" parameter
has 'pull_after_push_mode' => (is => 'rw',
                               default => 1);

state $global_id = int(rand(10000));

sub _build_ua {
    my $self = shift;
    return LWP::UserAgent->new(agent => 'Zabbix API client (libwww-perl)');
}

sub useragent {
    return shift->ua;
}

sub api_version {
    my $self = shift;
    # can't use _raw_query here because the server refuses the request
    # if an auth parameter is present -- wtf zabbix
    my $response = eval { $self->ua->post($self->server,
                                          'Content-Type' => 'application/json-rpc',
                                          Content => encode_json({
                                              jsonrpc => '2.0',
                                              id => $global_id++,
                                              method => 'apiinfo.version',
                                                                 })) };

    if (my $error = $@) {
        # no good
        croak sprintf('Could not request API version info: %s (%s, %s)',
                      $error, $response->code, $response->message);
    }

    my $decoded = eval { decode_json($response->decoded_content) };

    if (my $error = $@) {
        # no good either
        croak sprintf('Could not request API version info: %s (%s, %s)',
                      $error, $response->code, $response->message);
    }

    if ($decoded->{error}) {
        croak 'Could not request API version info: '.$decoded->{error}->{data};
    }

    return $decoded->{result};
}

sub login {
    my $self = shift;
    my %args = validate(@_, { user => 1,
                              password => 1 });
    $self->_clear_cookie;
    $self->_clear_user;

    my $response = $self->_raw_query(method => 'user.login',
                                     params => \%args);
    my $decoded = eval { decode_json($response->decoded_content) };

    if (my $error = $@) {
        # probably could not connect at all
        croak sprintf('Could not connect: %s (%s, %s)',
                      $error, $response->code, $response->message);
    }

    if ($decoded->{error}) {
        croak 'Could not log in: '.$decoded->{error}->{data};
    }

    $self->_set_cookie($decoded->{result});
    $self->_set_user($args{user});

    return $self;
}

sub logout {

    my $self = shift;
    my $response = $self->_raw_query(method => 'user.logout');
    my $decoded = eval { decode_json($response->decoded_content) };

    if (my $error = $@) {
        # probably could not connect at all
        croak sprintf('Could not log out: %s (%s, %s)',
                      $error, $response->code, $response->message);
    }

    if ($decoded->{error}) {
        croak 'Could not log out: '.$decoded->{error}->{data};
    }

    $self->_clear_cookie;
    $self->_clear_user;

    return $self;
}

sub _raw_query {
    my ($self, %args) = @_;

    # common parameters
    $args{'jsonrpc'} = '2.0';
    $args{'auth'} = $self->cookie if $self->cookie;
    $args{'id'} = $global_id++;

    my $response = eval { $self->ua->post($self->server,
                                          'Content-Type' => 'application/json-rpc',
                                          Content => encode_json(\%args)) };

    if (my $error = $@) {
        confess $error;
    }

    Log::Any->get_logger->trace($response->request->as_string);
    Log::Any->get_logger->debug($response->as_string);

    return $response;
}

sub query {
    my $self = shift;
    my %args = validate(@_, { method => { TYPE => SCALAR },
                              params => { TYPE => HASHREF,
                                          optional => 1 }});

    my $response = $self->_raw_query(%args);

    if ($response->is_success) {
        my $decoded = decode_json($response->decoded_content);
        if ($decoded->{error}) {
            croak(sprintf('While calling method %s, Zabbix server replied: %s',
                          $args{method},
                          $decoded->{error}->{data}));
        }
        return $decoded->{result};
    }

    croak 'Received HTTP error: '.$response->decoded_content;
}

sub fetch {
    my $self = shift;
    my $class = shift;
    my %args = validate(@_,
                        { params => { type => HASHREF,
                                      default => {} } });

    $class =~ s/^(?:Zabbix2::API::)?/Zabbix2::API::/;

    unless (Module::Loaded::is_loaded($class)) {
        eval { Module::Load::load($class) };
        if (my $error = $@) {
            croak qq{Could not load class '$class': $error};
        }
        $class->can('new')
            or croak "Class '$class' does not implement required 'new' method";
        $class->can('_prefix')
            or croak "Class '$class' does not implement required '_prefix' method";
        $class->can('_extension')
            or croak "Class '$class' does not implement required '_extension' method";
    }

    my $response = $self->query(method => $class->_prefix('.get'),
                                params => {
                                    %{$args{params}},
                                    $class->_extension
                                });

    return [ map { $class->new(root => $self, data => $_)  } @{$response} ];
}

sub fetch_single {
    my ($self, $class, %args) = @_;

    my $results = $self->fetch($class, %args);
    my $result_count = scalar @{$results};

    if ($result_count > 1) {
        croak qq{Too many results for 'fetch_single': expected 0 or 1, got $result_count};
    }

    return $results->[0];
}

1;
__END__
=pod

=head1 NAME

Zabbix2::API -- Access the JSON-RPC API of a Zabbix server

=head1 SYNOPSIS

  use Zabbix2::API;

  my $zabbix = Zabbix2::API->new(server => 'http://example.com/zabbix/api_jsonrpc.php');

  eval { $zabbix->login(user => 'calvin',
                        password => 'hobbes') };

  if ($@) { die 'could not authenticate' };

  my $items = $zabbix->fetch('Item', params => { search => { ... } });

=head1 DESCRIPTION

This module is a Moo wrapper around the Zabbix 2.x JSON-RPC API.

For the Zabbix 1.8.x series, see L<Zabbix::API>, which happens to
retain some limited degree of usefulness with Zabbix 2.x.

What you need to start hacking is probably the C<fetch> method in
C<Zabbix2::API>; be sure to check out also what the various
C<Zabbix2::API::Foo> classes do, as this is how you'll be manipulating
the objects you have just fetched.

=head1 ATTRIBUTES

=head2 cookie

(read-only string, with predicate)

This attribute is set after a successful login.  The value is a valid
Zabbix session cookie for all intents and purposes; it will be sent in
the "auth" key of each JSON-RPC method call.  It is unset after a
successful logout.

Interestingly, it is also valid for a regular HTTP "Cookie" header,
and you can use this fact to your advantage to send arbitrary HTTP
requests to the Zabbix server, allowing you to e.g. fetch graph images
with a valid user session.

=head2 pull_after_push_mode

(read-write boolean, defaults to a true value)

This attribute controls whether updating operations (calling C<create>
or C<update> on Zabbix objects) are immediately followed by an
automatic C<pull> on the object, to retrieve server-generated values
such as IDs.  Disabling this behavior causes write operations to
become faster, which is handy for a pure-provisioning workflow.

=head2 server

(read-only required string)

This must be set to the API endpoint of the Zabbix server.  This is
usually an HTTP URL of the form

  http://example.com/zabbix/api_jsonrpc.php

All API requests will be made to this URL.

=head2 ua

(read-only L<LWP::UserAgent> instance)

All HTTP requests will be performed by this object.  By default, it is
a vanilla L<LWP::UserAgent> instance with all attributes at their
default value except for the User-Agent string, which is set to
"Zabbix API client (libwww-perl)".

=head2 user

(read-only string, cannot be initialized in the constructor)

This attribute is set to the current user's username after a
successful login, and unset after a successful logout.

=head1 METHODS

=head2 api_version

  my $version = $zabbix->api_version;

Query the Zabbix server for the API version number and return it.

=head2 fetch

  my $things_aref = $zabbix->fetch('SomeClass', params => { ... });

This method fetches objects from the server.  The C<params> hashref
should contain API method parameters that identify the objects you're
trying to fetch, for instance:

  $zabbix->fetch('Item', params => {
      search => { key_ => 'system.uptime' } });

The default value of C<params> is an empty hashref, which B<should>
mean "fetch every object of type CLASS".  See the Zabbix server API
documentation
L<here|https://www.zabbix.com/documentation/2.2/manual/api/reference>.

The method delegates a lot of work to the CLASS so that it can be as
generic as possible.  Any CLASS name in the C<Zabbix2::API> namespace
is usable as long as it descends from C<Zabbix2::API::CRUDE> (to be
precise, it should implement a number of methods, some of which
C<CRUDE> implements, some of which are provided by specialized
subclasses provided in the distribution).  The string
C<Zabbix2::API::> will be prepended if it is missing.

Returns an arrayref of CLASS instances.

Note that if you pass it parameters that change the return type, such
as "countOutput", C<fetch> will be hopelessly confused, as it expects
the return value to be an array of object property maps.

=head2 fetch_single

  my $thing = $zabbix->fetch_single('SomeClass', params => { ... });

Like C<fetch>, but also checks how many objects the server sent back.
If no objects were sent, returns C<undef>.  If one object was sent,
returns that.  If more objects were sent, throws an exception.  This
helps against malformed queries; Zabbix tends to return B<all> objects
of a class when a query contains strange parameters (like "searhc" or
"fliter").

=head2 login

  $zabbix->login(user => 'me', password => 'mypassword');

Send login information to the Zabbix server and set the auth cookie if
the authentication was successful.

=head2 logout

  $zabbix->logout;

Terminate the current session.

=head2 query

  my $results = $zabbix->query(method => 'item.isreadable',
                               params => { ... });

This method encodes the parameters provided, sends an API request,
waits for the server response and decodes it.  It will throw an
exception if the server sends back an API error message or an HTTP
error.

=head2 useragent

  my $ua = $zabbix->useragent;

Alternative spelling of the C<ua> accessor.

=head1 TIPS AND TRICKS

=head2 SSL SUPPORT

L<LWP::UserAgent> supports SSL if you install L<LWP::Protocol::https>.
You may need to configure L<LWP::UserAgent> manually, e.g.

  my $zabbix = Zabbix2::API->new(
      ua => LWP::UserAgent->new(
          ssl_opts => { verify_hostname => 0,
                        SSL_verify_mode => 'SSL_VERIFY_NONE' }));

=head2 LOGGING

L<Zabbix2::API> uses L<Log::Any> to log outgoing requests and incoming
responses.

=head1 BUGS AND MISSING FEATURES

The C<user.logout> method has been broken ever since the first Zabbix
version that included an API.  It may have been fixed since.

Wrapping an API class requires a small but nonzero quantity of tuits
which I do not have.  Thus not all API classes are wrapped.  Patches
are welcome.

=head1 CHANGES FROM Zabbix::API

=head2 THE verbosity ATTRIBUTE

This attribute has been removed in favor of L<Log::Any>-based logging.
See also the documentation of L<Log::Any::Adapter>.

=head2 THE cache ATTRIBUTE

This feature was never very useful.  It has been removed to make the
code simpler and (hopefully) less bug-prone.

=head2 USAGE OF Moo

L<Zabbix::API> used plain Perl objects, mostly due to constraints that
existed on the system for which it was originally written.  This
version uses L<Moo>, which removes a lot of boilerplate and makes the
code clearer.

=head2 THE _readonly_properties METHOD

Zabbix 1.8.x used to silently ignore read-only properties sent as part
of an update or create operation.  However, Zabbix 2.x returns an
error if they are provided, even if they have not been changed from
the value stored on the server.  This means that most subclasses of
L<Zabbix2::API::CRUDE> need to implement this method to filter out the
list of properties that must be removed before calling C<update> or
C<create>.

=head2 push VS create/update/exists

In L<Zabbix::API>, you could call C<< $thing->push; >> and it would
magically do things depending on if it thought the thing already
existed on the server.  This was well-suited to our initial usage, but
it proved problematic to maintain and hard to adapt to other
workflows.

L<Zabbix2::API> has replaced the C<push> method with explicit
C<create>, C<update> and C<exists> methods.

=head1 CONTRIBUTING

If you wish to contribute to this project, e.g. by writing a class
wrapper or fixing bugs etc., I would appreciate if you wrote the
attendant unit tests.

All unit tests in F<t/> are run against a live Zabbix instance,
canonically the one provided by L<this Docker
service|https://index.docker.io/u/berngp/docker-zabbix/>.

=head1 SEE ALSO

The Zabbix API documentation, at L<http://www.zabbix.com/documentation/start>

L<LWP::UserAgent>

=head1 AUTHOR

Fabrice Gabolde <fga@cpan.org>, Sujit Sali <sujitsali@cpan.org>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011, 2012, 2013, 2014 SFR

This library is free software; you can redistribute it and/or modify
it under the terms of the GPLv3.

=cut
