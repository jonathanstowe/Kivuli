#!/usr/bin/env raku

use Test;
use Kivuli;

my $cred-data = $*PROGRAM.parent.add("data/creds.json").slurp;

my Kivuli::Credentials $creds;

lives-ok { $creds = Kivuli::Credentials.from-json($cred-data) },"get credentials from data";


done-testing;
# vim: ft=raku
