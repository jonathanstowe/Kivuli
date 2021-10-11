=begin pod

=head1 NAME

Kivuli - get AWS IAM credentials for EC2

=head1 SYNOPSIS

=begin code

# In some application running on EC2

use Kivuli;
use WebService::AWS::S3;

my $k = Kivuli.new(role-name => 'my-iam-role');
my $s3 = WebService::AWS::S3.new(secret-access-key => $k.secret-access-key, access-key-id => $k.access-key-id, security-token => $k.token, region => 'eu-west-2');

# Do something with the S3

=end code

=head1 DESCRIPTION

This module enables access to AWS IAM role
credentials from within an EC2 instance as L<described
here|https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html>.

The credentials supplied ( C<AWS_ACCESS_KEY_ID>,
C<AWS_SECRET_ACCESS_KEY>,) can be used to authenticate with another AWS
service that the role has been granted access to.

Because the credentials are supplied in a way that is private to the EC2
instance this is a more secure method of obtaining the credentials than,
for example, putting them in a configuration file.

The C<token> B<must> be supplied in the headers (or as a query parameter,)
for requests to the service, however some services differ as to whether it
should or shouldn't be part of the signed headers in the request - please
see the documentation for the service you are implementing for details.

For convenience the credentials are supplied as accessors on the object, and optionally
(with the C<:environment> switch to the constructor,) as environment variables ( C<AWS_ACCESS_KEY_ID>,
C<AWS_SECRET_ACCESS_KEY>, C<AWS_SESSION_TOKEN>,) which may be useful if integrating
with tools that use them.

Optionally the credentials can be I<refreshed> if the C<:refresh> switch is applied to the constructor,
that is to say one minute before the expiration of the existing credentials, the credentials will be
re-fetched when they are next accessed (if C<:environment> is specified as well the environment variables
will be refreshed immediately.)  For convenience the C<refresh-supply> will emit an event whenever the
refresh is triggered, this can be tapped if other parts of the application may need to change their state.

If an attempt to retrieve the credentials fails (e.g. you are running this on somewhere other than EC2,
or you are running on EC2 but no IAM role has been associated with the EC2 instance,) then an exception will
be thrown.

If you are using this in an ElasticBeanstalk instance rather than directly on EC2 then you will need to use
the C<:no-api-token> switch to the constructor, this will suppress the attempt to get a temporary session
token which appears not to work in the EB Docker container.

=head2 METHODS

=end pod

class Kivuli {
    use Cro::HTTP::Client;
    use JSON::Name;
    use JSON::Class;
    class Credentials does JSON::Class {

        sub unmarshal-datetime( Str $v --> DateTime ) {
            DateTime.new($v);
        }

        has DateTime    $.last-updated      is json-name('LastUpdated') is unmarshalled-by(&unmarshal-datetime);
        has Str         $.type              is json-name('Type');
        has Str         $.token             is json-name('Token');
        has Str         $.secret-access-key is json-name('SecretAccessKey');
        has Str         $.code              is json-name('Code');
        has DateTime    $.expiration-time   is json-name('Expiration') is unmarshalled-by(&unmarshal-datetime);
        has Str         $.access-key-id     is json-name('AccessKeyId');

        has Promise     $.expiry-promise    is json-skip;

        method expiry-promise( --> Promise ) {
            $!expiry-promise //= Promise.at($.expiration-time.earlier(minutes => 1).Instant);
        }
    }

    #| The name of the IAM role the credentials are for, if not set will attempt to autodiscover
    has Str $.role-name;

    method role-name( --> Str ) {
        $!role-name //= await $.get-role-name;

    }

    #| If set to true on the constructor, the temporary api token will not be
    #| retrieved and will not be sent in the headers of subsequent requests
    has Bool $.no-api-token = False;

    #| If set to true at the constructor will set the appropriate environment
    #| variables.
    has Bool $.environment = False;

    #| If set to true then a refresh of the credentials will be forced
    #| approximately one minute before the expiry time
    has Bool $.refresh     = False;

    #| An object representing the obtained credentials to which the
    #| access-key-id, secret-access-key and token are delegated
    has Credentials $.credentials;

    method credentials( --> Credentials ) handles <access-key-id secret-access-key token> {
        $!credentials //= await self.get-credentials();
    }

    #| public because it may be set for testing, the default must be used in EC2
    has Str         $.base-uri  = 'http://169.254.169.254/latest/';

    #| The token's time to live - default is six hours
    has Int         $.token-ttl-seconds = 21600;

    has Cro::HTTP::Client $.http-client;
    method http-client( --> Cro::HTTP::Client ) handles <get put> {
        $!http-client //= Cro::HTTP::Client.new(:$!base-uri);
    }

    has Supplier $!refresh-supplier = Supplier.new;

    has Supply   $.refresh-supply;

    #| This is a supply that has an event emitted whenever the credentials
    #| are refreshed (assuming :refresh was supplied to the constructor.)
    method refresh-supply( --> Supply ) {
        $!refresh-supply //= $!refresh-supplier.Supply;
    }

    #| Returns a Promise which will be kept with the AWS token to be used for the credentials request
    #| This is probably not useful in user code as the token can only be used in a subsequent credential
    #| request. If ':no-api-token' was provided to the constructor, this will be an undefined Str - the
    #| consuming code should not use it in that case.
    method get-token( --> Promise ) {
        (supply {
            if $!no-api-token {
                emit Str;
                done;
            }
            else {
                whenever self.put("api/token", headers => [ X-aws-ec2-metadata-token-ttl-seconds => $.token-ttl-seconds ] ) -> $r {
                    whenever $r.body-text -> $token {
                        emit $token;
                        done;
                    }
                }
            }
        }).Promise;
    }

    #| Returns a Promise whill be kept with the Kivuli::Credentials object.  This is invoked by the C<credentials> accessor
    #| so is not needed in normal use, but may be useful in e.g. a sub-class.
    method get-credentials( --> Promise ) {
        ( supply {
            whenever self.get-token() -> $token {
                whenever self.get("meta-data/iam/security-credentials/" ~ self.role-name, |(headers => [ X-aws-ec2-metadata-token => $_ ] with $token )) -> $r {
                    whenever $r.body-text -> $body {
                        my $creds = Credentials.from-json($body);
                        if $.refresh {
                            $creds.expiry-promise.then({
                                $!refresh-supplier.emit: $creds.expiration-time;
                                $!credentials = Nil;
                                if $.environment {
                                    $.set-environment();
                                }
                            });
                        }
                        emit $creds;
                        done;
                    }
                }
            }
        }).Promise;
    }

    #| returns a promise which will be kept with role-name to be used,  this will be used if there is no role-name supplied
    #| to the constructor.  Under normal circumstances you'd probably want to use the role-name accessor.
    method get-role-name( --> Promise ) {
        ( supply {
            whenever self.get-token() -> $token {
                whenever self.get("meta-data/iam/security-credentials", |(headers => [ X-aws-ec2-metadata-token => $_ ] with $token ) ) -> $r {
                    whenever $r.body-text -> $body {
                        emit $body;
                        done;
                    }
                }
            }
        }).Promise;
    }

    method new(|c) {
        my $self = callsame;
        if $self.environment {
            $self.set-environment();
        }
        $self;
    }

    #| This sets the environment variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN
    #| from the retrieved credentials (causing a retrieval if necessary,)  this will be called immediately
    #| after the object is constructed if the :environment switch is applied to the constructor.  Calling
    #| this explicitly may be useful if you have some integration where they shouldn't be set followed
    #| by one where they must.
    method set-environment(--> Nil) {
        %*ENV<AWS_ACCESS_KEY_ID>        = $.access-key-id;
        %*ENV<AWS_SECRET_ACCESS_KEY>    = $.secret-access-key;
        %*ENV<AWS_SESSION_TOKEN>        = $.token;
    }
}

# vim: ft=raku
