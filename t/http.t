package test::Wanage::HTTP;
use strict;
use warnings;
use Path::Class;
use lib file (__FILE__)->dir->parent->subdir ('lib')->stringify;
use lib glob file (__FILE__)->dir->parent->subdir ('modules', '*', 'lib')->stringify;
use lib file (__FILE__)->dir->parent->subdir ('t', 'lib')->stringify;
use Wanage::HTTP;
use base qw(Test::Class);
use Encode;
use Test::MoreMore;
use Test::Wanage::Envs;

$Wanage::HTTP::Sortkeys = 1;

sub _version : Test(1) {
  ok $Wanage::HTTP::VERSION;
} # _version

# ------ Constructors ------

sub _new_cgi : Test(3) {
  my $http = with_cgi_env {
    Wanage::HTTP->new_cgi;
  } {HTTP_HOGE => 123};
  isa_ok $http, 'Wanage::HTTP';
  isa_ok $http->{interface}, 'Wanage::Interface::CGI';
  is $http->get_request_header ('Hoge'), '123';
} # _new_cgi

sub _new_from_psgi_env : Test(3) {
  my $env = new_psgi_env {HTTP_HOGE => 123};
  my $http = Wanage::HTTP->new_from_psgi_env ($env);
  isa_ok $http, 'Wanage::HTTP';
  isa_ok $http->{interface}, 'Wanage::Interface::PSGI';
  is $http->get_request_header ('Hoge'), '123';
} # _new_from_psgi_env

# ------ Request URL ------

sub _url : Test(14) {
  my $https = new_https_for_interfaces
      env => {HTTP_HOST => q<hoge.TEST>, REQUEST_URI => "/hoge/?abc\xFE\xC5",
              'psgi.url_scheme' => 'http'};
  for my $http (@$https) {
    my $url = $http->url;
    isa_ok $url, 'Wanage::URL';
    is $url->{scheme}, 'http';
    is $url->{host}, 'hoge.test';
    is $url->{path}, q</hoge/>;
    is $url->{query}, q<abc%EF%BF%BD%EF%BF%BD>;
    is $http->url, $url;
    isnt $http->original_url, $url;
  }
} # _url

sub _original_url : Test(14) {
  my $https = new_https_for_interfaces
      env => {HTTP_HOST => q<hoge.TEST>, REQUEST_URI => "/hoge/?abc\xFE\xC5",
              'psgi.url_scheme' => 'http'};
  for my $http (@$https) {
    my $url = $http->original_url;
    isa_ok $url, 'Wanage::URL';
    is $url->{scheme}, 'http';
    is $url->{host}, 'hoge.TEST';
    is $url->{path}, q</hoge/>;
    is $url->{query}, qq<abc\x{FFFD}\x{FFFD}>;
    is $http->original_url, $url;
    isnt $http->url, $url;
  }
} # _original_url

sub _query_params : Test(14) {
  for (
    [undef, {}],
    ['' => {}],
    ['0' => {'0' => [""]}],
    ['abc=%26%A9' => {abc => ["&\xA9"]}],
    ['hoge=xy&hoge=aa' => {hoge => ["xy", "aa"]}],
    ["aaa=bbb&ccc=dd;" => {'' => [''], aaa => ["bbb"], ccc => ["dd"]}],
    ["===" => {'' => ["=="]}],
  ) {
    my $https = new_https_for_interfaces
        env => {QUERY_STRING => $_->[0]};
    for my $http (@$https) {
      eq_or_diff $http->query_params, $_->[1];
    }
  }
} # _query_params

sub _query_params_same : Test(2) {
  my $https = new_https_for_interfaces;
  for my $http (@$https) {
    is $http->query_params, $http->query_params;
  }
} # _query_params_same

# ------ Request method ------

sub _request_method : Test(78) {
  for (
    [undef, undef, 0, 0],
    ['' => '', 0, 0],
    ['0' => '0', 0, 0],
    ['GET' => 'GET', 1, 1],
    ['get' => 'GET', 1, 1],
    ['Get' => 'GET', 1, 1],
    ['POST' => 'POST', 0, 0],
    ['HEAD' => 'HEAD', 1, 1],
    ['PUT' => 'PUT', 0, 1],
    ['DELETE' => 'DELETE', 0, 1],
    ['OPTIONS' => 'OPTIONS', 0, 1],
    ['unknown method' => 'unknown method', 0, 0],
    ['Get123' => 'Get123', 0, 0],
  ) {
    my $https = new_https_for_interfaces
        env => {REQUEST_METHOD => $_->[0]};
    for my $http (@$https) {
      is $http->request_method, $_->[1];
      is_bool $http->request_method_is_safe, $_->[2];
      is_bool $http->request_method_is_idempotent, $_->[3];
    }
  }
} # _request_method

# ------ Request headers ------

sub _get_request_header : Test(10) {
  my $https = new_https_for_interfaces
      env => {HTTP_HOGE_FUGA => 'abc def,abc',
              CONTENT_TYPE => 'text/html',
              CONTENT_LENGTH => 351,
              HTTP_AUTHORIZATION => 'hoge fauga'};
  for my $http (@$https) {
    is $http->get_request_header ('Hoge-Fuga'), 'abc def,abc';
    is $http->get_request_header ('X-hoge-fuga'), undef;
    is $http->get_request_header ('Content-Type'), 'text/html';
    is $http->get_request_header ('Content-Length'), 351;
    is $http->get_request_header ('Authorization'), 'hoge fauga';
  }
} # _get_request_header

# ------ Request body -----

sub _request_body_as_ref_no_body : Test(2) {
  my $https = new_https_for_interfaces;
  for my $http (@$https) {
    is $http->request_body_as_ref, undef;
  }
} # _request_body_as_ref_no_body

sub _request_body_as_ref_with_body : Test(4) {
  my $https = new_https_for_interfaces
      env => {CONTENT_LENGTH => 10},
      request_body => "abc\x40\x9F\xCDaaagewgeeee";
  for my $http (@$https) {
    my $ref = $http->request_body_as_ref;
    is $$ref, "abc\x40\x9F\xCDaaag";
    is $http->request_body_as_ref, $ref;
  }
} # _request_body_as_ref_with_body

sub _request_body_as_ref_with_body_too_short : Test(4) {
  my $https = new_https_for_interfaces
      env => {CONTENT_LENGTH => 100},
      request_body => "abc\x40\x9F\xCDaaagewgeeee";
  for my $http (@$https) {
    dies_here_ok { $http->request_body_as_ref };
    dies_here_ok { $http->request_body_as_ref };
  }
} # _request_body_as_ref_with_body_too_short

sub _request_body_as_ref_zero_body : Test(4) {
  my $https = new_https_for_interfaces
      env => {CONTENT_LENGTH => 0},
      request_body => "";
  for my $http (@$https) {
    my $ref = $http->request_body_as_ref;
    is $$ref, "";
    is $http->request_body_as_ref, $ref;
  }
} # _request_body_as_ref_zero_body

sub _request_body_params_no_body : Test(16) {
  for my $ct (
    undef,
    'application/x-hoge-fuga',
    'application/x-www-form-urlencoded',
    'Application/x-www-FORM-urlencoded',
  ) {
    my $https = new_https_for_interfaces;
    for my $http (@$https) {
      my $params = $http->request_body_params;
      eq_or_diff $params, {};
      is $http->request_body_params, $params;
    }
  }
} # _request_body_params_no_body

sub _request_body_params_zero_body : Test(16) {
  for my $ct (
    undef,
    'application/x-hoge-fuga',
    'application/x-www-form-urlencoded',
    'Application/x-www-FORM-urlencoded',
  ) {
    my $https = new_https_for_interfaces
        env => {CONTENT_LENGTH => 0, CONTENT_TYPE => $ct},
        request_body => '';
    for my $http (@$https) {
      my $params = $http->request_body_params;
      eq_or_diff $params, {};
      is $http->request_body_params, $params;
    }
  }
} # _request_body_params_zero_body

sub _request_body_params_zero_with_body_bad_type : Test(8) {
  for my $ct (
    undef,
    'application/x-hoge-fuga',
  ) {
    my $https = new_https_for_interfaces
        env => {CONTENT_LENGTH => 19, CONTENT_TYPE => $ct},
        request_body => 'hogfe=fauga&abc=def';
    for my $http (@$https) {
      my $params = $http->request_body_params;
      eq_or_diff $params, {};
      is $http->request_body_params, $params;
    }
  }
} # _request_body_params_with_body_bad_type

sub _request_body_params_zero_with_body_with_type : Test(16) {
  for my $ct (
    'application/x-www-form-urlencoded',
    'Application/x-www-form-URLencoded',
    'application/x-www-form-urlencoded; charset=utf-8',
    'application/x-www-form-urlencoded ;charset=utf-8',
  ) {
    my $https = new_https_for_interfaces
        env => {CONTENT_LENGTH => 19, CONTENT_TYPE => $ct},
        request_body => 'hogfe=fauga&abc=def';
    for my $http (@$https) {
      my $params = $http->request_body_params;
      eq_or_diff $params, {hogfe => ['fauga'], abc => ['def']};
      is $http->request_body_params, $params;
    }
  }
} # _request_body_params_with_body_with_type

# ------ Response ------

sub _send_response_empty_cgi : Test(3) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->close_response_body;
  is $out, "Status: 200 OK\n\n";
} # _send_response_empty_cgi

sub _send_response_empty_psgi : Test(2) {
  my $http = Wanage::HTTP->new_from_psgi_env (new_psgi_env);
  eq_or_diff $http->send_response, [200, [], []];
  dies_here_ok { $http->close_response_body };
} # _send_response_empty_psgi

sub _send_response_empty_psgi_streamable : Test(6) {
  my $http = Wanage::HTTP->new_from_psgi_env
      (new_psgi_env {'psgi.streaming' => 1});
  my $writer = Test::Wanage::Envs::PSGI::Writer->new;
  my $res;
  $http->send_response->(sub { $res = shift; return $writer });
  eq_or_diff $res, undef;
  eq_or_diff $writer->data, [];
  ng $writer->closed;
  $http->close_response_body;
  eq_or_diff $res, [200, []];
  eq_or_diff $writer->data, [];
  ok $writer->closed;
} # _send_response_empty_psgi_streamable

sub _send_response_methods_cgi : Test(3) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->set_status (402 => "Test\n1");
  $http->set_response_header ('X-Hoge-Fuga' => 123);
  $http->set_response_header ('X_Hoge-Fuga' => "abc def\n\x90");
  $http->add_response_header ('X-Hoge-fuga' => 520);
  $http->set_response_header ("x-Hoge fuga:" => "abc");
  $http->send_response_body_as_ref (\"ab \nxzyz");
  $http->send_response_body_as_ref (\"0");
  eq_or_diff $out, "Status: 402 Test 1
X-Hoge-Fuga: 123
X-Hoge-fuga: 520
X_Hoge-Fuga: abc def \x90
x-Hoge_fuga_: abc

ab\x20
xzyz0";
} # _send_response_methods_cgi

sub _send_response_methods_psgi : Test(1) {
  my $http = Wanage::HTTP->new_from_psgi_env (new_psgi_env);
  $http->set_status (402 => "Test\n1");
  $http->set_response_header ('X-Hoge-Fuga' => 123);
  $http->set_response_header ('X_Hoge-Fuga' => "abc def\n\x90");
  $http->add_response_header ('X-Hoge-fuga' => 520);
  $http->set_response_header ("x-Hoge fuga:" => "abc");
  $http->send_response_body_as_ref (\"ab \nxzyz");
  $http->send_response_body_as_ref (\"0");
  eq_or_diff $http->send_response, [402,
                       ['X-Hoge-Fuga' => '123',
                        'X-Hoge-fuga' => '520',
                        'X_Hoge-Fuga' => "abc def\x0A\x90",
                        "x-Hoge fuga:" => 'abc'],
                       ["ab\x20\nxzyz", "0"]];
} # _send_response_methods_psgi

sub _set_status_cgi : Test(4) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->set_status (402 => "Test\n1");
  $http->set_status (103 => "Hoge \x00fuga\x0D");
  $http->send_response_body_as_ref (\"");
  dies_here_ok { $http->set_status (501) };
  eq_or_diff $out, "Status: 103 Hoge \x00fuga \n\n";
} # _set_status_cgi

sub _set_status_default_text_cgi : Test(3) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->set_status (205);
  $http->send_response_body_as_ref (\"");
  eq_or_diff $out, "Status: 205 Reset Content\n\n";
} # _set_status_default_text_cgi

sub _set_response_header_cgi : Test(4) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->set_response_header ('X-Hoge' => 'ab cd');
  $http->set_response_header ('X-Hoge' => 'xy zz');
  $http->set_response_header ('X-ABC' => '111');
  $http->send_response_body_as_ref (\"");
  dies_here_ok { $http->set_response_header ('X-Hoge' => '1234') };
  eq_or_diff $out, "Status: 200 OK\nX-ABC: 111\nX-Hoge: xy zz\n\n";
} # _set_response_header_cgi

sub _add_response_header_cgi : Test(4) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  ng $http->send_response;
  is $out, '';
  $http->set_response_header ('X-Hoge' => 'zab cd');
  $http->add_response_header ('X-Hoge' => 'xy zz');
  $http->add_response_header ('X-ABC' => ' 111');
  $http->send_response_headers;
  dies_here_ok { $http->add_response_header ('X-Hoge' => '1234') };
  eq_or_diff $out, "Status: 200 OK\nX-ABC:  111\nX-Hoge: zab cd\nX-Hoge: xy zz\n\n";
} # _add_response_header_cgi

sub _send_response_headers_twice : Test(2) {
  my $https = new_https_for_interfaces;
  for my $http (@$https) {
    $http->send_response_headers;
    dies_here_ok { $http->send_response_headers };
  }
} # _send_response_headers_twice

sub _send_response_body_as_text : Test(1) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  $http->send_response_body_as_text ("\x{4340}abc");
  $http->send_response_body_as_text ("\xAc\xFE\x45\x00ab");
  is $out, "Status: 200 OK\n\n" .
      encode 'utf-8', "\x{4340}abc\xAc\xFE\x45\x00ab";
} # _send_response_body_as_text

sub _send_response_body_as_ref : Test(1) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  $http->send_response_body_as_ref (\"\xFEabc");
  $http->send_response_body_as_ref (\"\xAc\xFE\x45\x00ab");
  $http->send_response_body_as_ref (\"");
  $http->send_response_body_as_ref (\"0");
  is $out, "Status: 200 OK\n\n\xFEabc\xAc\xFE\x45\x00ab0";
} # _send_response_body_as_ref

sub _close_response_body : Test(7) {
  my $out = '';
  my $http = with_cgi_env { Wanage::HTTP->new_cgi } {}, undef, $out;
  $http->close_response_body;
  dies_here_ok { $http->set_status (201) };
  dies_here_ok { $http->set_response_header (1 => 2) };
  dies_here_ok { $http->add_response_header (3 => 4) };
  dies_here_ok { $http->send_response_headers };
  dies_here_ok { $http->send_response_body_as_ref (\"") };
  dies_here_ok { $http->send_response_body_as_text ("") };
  dies_here_ok { $http->close_response_body };
} # _close_response_body

sub _send_response_psgi_streamable_multiple : Test(3) {
  my $http = Wanage::HTTP->new_from_psgi_env
      (new_psgi_env {'psgi.streaming' => 1});
  my $writer = Test::Wanage::Envs::PSGI::Writer->new;
  my $res;
  $http->send_response (onready => sub {
    $http->set_status (501);
    $http->add_response_header ('Content-Type' => 'text/plain; charset=utf-8');
    $http->send_response_body_as_text ("\x{1055}");
    $http->send_response_body_as_text ("0");
    $http->close_response_body;
  })->(sub { $res = shift; return $writer });
  eq_or_diff $res, [501, ['Content-Type' => 'text/plain; charset=utf-8']];
  eq_or_diff $writer->data, [(encode 'utf-8', "\x{1055}"), "0"];
  ok $writer->closed;
} # _send_response_empty_psgi_streamable

__PACKAGE__->runtests;

1;

=head1 LICENSE

Copyright 2012 Wakaba <w@suika.fam.cx>.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
