#!/usr/bin/env raku

use Test;
use Test::Mock;
use Kivuli;
use JSON::Fast;

use Cro::HTTP::Client;
use Cro::HTTP::Response;

my $put-response = mocked(Cro::HTTP::Response, returning => {
    body-text   =>  Promise.kept( 'AHBDSISKSKSCL'),
});

my $creds = $*PROGRAM.parent.add('data/creds.json').slurp;

my %creds = from-json($creds);
%creds<Expiration> = DateTime.now.later(seconds => 65).Str;
$creds = to-json(%creds);

my $get-response = mocked(Cro::HTTP::Response, returning => {
    body-text   => Promise.kept($creds),
});

my $http-client = mocked(Cro::HTTP::Client, returning => {
    get =>  Promise.kept($get-response),
    put =>  Promise.kept( $put-response )
});

my $kivuli;

lives-ok { $kivuli = Kivuli.new(:$http-client, role-name => 'my-test-role', :refresh) }, "create kivuli object";

my $p = Promise.new;

$kivuli.refresh-supply.tap({
    $p.keep;
});

is $kivuli.access-key-id, %creds<AccessKeyId>, "access-key-id";
is $kivuli.secret-access-key, %creds<SecretAccessKey>, "secret-access-key";
is $kivuli.token, %creds<Token>, "token";

await Promise.anyof($p, Promise.in(90));
ok $p, "the refresh occurred";

done-testing;
# vim: ft=raku
