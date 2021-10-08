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

my $get-response = mocked(Cro::HTTP::Response, returning => {
    body-text   => Promise.kept($creds),
});

my $http-client = mocked(Cro::HTTP::Client, returning => {
    get =>  Promise.kept($get-response),
    put =>  Promise.kept( $put-response )
});

subtest {
    my $kivuli;

    lives-ok { $kivuli = Kivuli.new(:$http-client, role-name => 'my-test-role', :environment, :refresh) }, "create kivuli object";

    my %creds = from-json($creds);

    is $kivuli.access-key-id, %creds<AccessKeyId>, "access-key-id";
    is $kivuli.secret-access-key, %creds<SecretAccessKey>, "secret-access-key";
    is $kivuli.token, %creds<Token>, "token";

    lives-ok { $kivuli.set-environment }, 'Set environment';

    is %*ENV<AWS_ACCESS_KEY_ID>, %creds<AccessKeyId>, "AWS_ACCESS_KEY_ID";
    is %*ENV<AWS_SECRET_ACCESS_KEY>, %creds<SecretAccessKey>, "AWS_SECRET_ACCESS_KEY";
    is %*ENV<AWS_SESSION_TOKEN>, %creds<Token>, "AWS_SESSION_TOKEN";
}, 'with API token';
subtest {
    my $kivuli;

    lives-ok { $kivuli = Kivuli.new(:$http-client, role-name => 'my-test-role', :no-api-token, :environment, :refresh) }, "create kivuli object";

    my %creds = from-json($creds);

    is $kivuli.access-key-id, %creds<AccessKeyId>, "access-key-id";
    is $kivuli.secret-access-key, %creds<SecretAccessKey>, "secret-access-key";
    is $kivuli.token, %creds<Token>, "token";
    ok !(await $kivuli.get-token).defined, "get-token returns undefined with :no-api-token";

    lives-ok { $kivuli.set-environment }, 'Set environment';

    is %*ENV<AWS_ACCESS_KEY_ID>, %creds<AccessKeyId>, "AWS_ACCESS_KEY_ID";
    is %*ENV<AWS_SECRET_ACCESS_KEY>, %creds<SecretAccessKey>, "AWS_SECRET_ACCESS_KEY";
    is %*ENV<AWS_SESSION_TOKEN>, %creds<Token>, "AWS_SESSION_TOKEN";
}, 'without API token';


done-testing;
# vim: ft=raku
