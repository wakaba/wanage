package Wanage::Interface::CGI;
use strict;
use warnings;
our $VERSION = '3.0';
use Carp;
use Web::Encoding;
use IO::Handle;
use Wanage::Interface::Base;
push our @ISA, qw(Wanage::Interface::Base);

# ------ Constructor ------

sub new_from_main ($) {
  return bless {
    env => \%ENV,
    request_body_handle => *STDIN{IO},
    response_handle => *STDOUT{IO},
  }, $_[0];
} # new_from_main

# ------ Request data ------

sub url_scheme ($) {
  return $_[0]->{url_scheme} ||= (
    $_[0]->_url_scheme_by_proxy ||
    ((($_[0]->{env}->{HTTPS} || '') =~ /^(?:[Oo][Nn]|1)$/) ? 'https' : 'http')
  );
} # url_scheme

sub get_meta_variable ($$) {
  return $_[0]->{env}->{$_[1]};
} # get_meta_variable

sub get_request_body_as_ref ($) {
  my $length = $_[0]->{env}->{CONTENT_LENGTH};
  return undef unless defined $length;
  croak "Request body has already been read" if $_[0]->{request_body_read};
  my $buf = '';
  $_[0]->{request_body_handle}->read ($buf, $length);
  croak "CGI error: premature end of input"
      unless $length == length $buf;
  $_[0]->{request_body_read} = 1;
  return \$buf;
} # get_request_body_as_ref

sub get_request_body_as_handle ($) {
  my $length = $_[0]->{env}->{CONTENT_LENGTH};
  return undef unless defined $length;
  croak "Request body has already been read" if $_[0]->{request_body_read};
  $_[0]->{request_body_read} = 1;
  return $_[0]->{request_body_handle};
} # get_request_body_as_handle

# ------ Response ------

sub set_response_headers ($$) {
  croak "You can no longer set response headers"
      if $_[0]->{response_headers_sent};
  $_[0]->{response_headers} = $_[1];
  $_[0]->{has_response} = 1;
} # set_response_headers

sub send_response_headers ($;%) {
  my ($self, %args) = @_;
  croak "Response body is already closed" if $self->{response_body_closed};
  if ($self->{response_headers_sent}) {
    if (defined $args{status} or
        defined $args{status_text} or
        $args{headers}) {
      croak "You can no longer set response headers";
    }
    return;
  }
  my $handle = $self->{response_handle};
  $self->{has_response} = 1;

  my $status = $args{status};
  $status = 200 if not defined $status;
  $status = 0 + $status;
  my $status_text = $args{status_text};
  $status_text = do {
    require Wanage::HTTP::Info;
    $Wanage::HTTP::Info::ReasonPhrases->{$status} || '';
  } unless defined $status_text;
  $status_text =~ s/\s+/ /g;
  $status_text = encode_web_utf8 $status_text if utf8::is_utf8 ($status_text);

  print $handle "Status: $status $status_text\n";
  for (@{$args{headers} or []}) {
    my $name = $_->[0];
    my $value = $_->[1];
    $name =~ s/[^0-9A-Za-z_-]/_/g; ## Far more restrictive than RFC 3875
    $value =~ s/[\x0D\x0A]+[\x09\x20]*/ /g;
    $name = encode_web_utf8 $name if utf8::is_utf8 ($name);
    $value = encode_web_utf8 $value if utf8::is_utf8 ($value);
    print $handle "$name: $value\n";
  }
  print $handle "\n";
  
  $self->{response_headers_sent} = 1;
} # send_response_headers

sub send_response_body ($$) {
  my $self = $_[0];
  croak "Response body is already closed" if $self->{response_body_closed};
  $self->send_response_headers;
  print { $self->{response_handle} } $_[1];
} # send_response_body

sub close_response_body ($) {
  my $self = shift;
  croak "Response body is already closed" if $self->{response_body_closed};
  $self->send_response_headers;
  ## Don't close filehandle since closing the STDOUT would cause the
  ## CGI script terminated in some system.
  #$self->{response_handle}->close or die $!;
  $self->{response_body_closed} = 1;
  $self->onclose->();
} # close_response_body

sub send_response ($;%) {
  my ($self, %args) = @_;
  my $code = $args{onready};
  croak "Response has already been sent" if $self->{response_sent};
  $self->{response_sent} = 1;
  $self->{has_response} = 1;
  $code->() if $code;
  return;
} # send_response

sub DESTROY {
  my $self = shift;
  if ($self->{has_response}) {
    if ($self->{response_sent} and not $self->{response_headers_sent}) {
      warn "Response is discarded before it is sent\n";
    }
    $self->close_response_body unless $self->{response_body_closed};
  }
} # DESTROY

1;

=head1 LICENSE

Copyright 2012-2018 Wakaba <wakaba@suikawiki.org>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
