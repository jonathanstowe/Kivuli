# Kivuli

Get AWS IAM role credentials in EC2

[![CI](https://github.com/jonathanstowe/Kivuli/actions/workflows/main.yml/badge.svg)](https://github.com/jonathanstowe/Kivuli/actions/workflows/main.yml)

## Synopsis

```raku

# In some application running on EC2

use Kivuli;
use WebService::AWS::S3;

my $k = Kivuli.new(role-name => 'my-iam-role');
my $s3 = WebService::AWS::S3.new(secret-access-key => $k.secret-access-key, access-key-id => $k.access-key-id, region => 'eu-west-2');

# Do something with the S3


```


## Description

This module enables access to AWS IAM role credentials from within an EC2 instance as [described here](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html).

The credentials supplied ( `AWS_ACCES_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,) can be used to authenticate with another AWS service that the role has been granted access to.

Because the credentials are supplied in a way that is private to the EC2 instance this is a more secure method of obtaining the credentials than, for example, putting them in a configuration file.

## Installation

Assuming you have a working _rakudo_ installation then you should be able to install this with *zef*:

     zef install Kivuli

Bear in mind that this will pass its tests and install outside an EC2 instance, which may be useful for example to build a Docker image to upload to AWS, but it will only work correctly on EC2.


## Support

This has some fairly specific environmental dependencies, so before raising an issue please check:

   *  You are running your application in an AWS EC2 instance
   *  That you have created the [IAM Role](https://docs.aws.amazon.com/IAM/latest/UserGuide/WorkingWithRoles.html), given it the required permissions and associated it your EC2 instance. 

Any suggestions/issues/etc can be posted to [github](https://github.com/jonathanstowe/Kivuli/issues) and I'll see what I can do.


# Licence and Copyright

This is free software please see the [LICENCE](LICENCE) in the distribution files.

© Jonathan Stowe 2021
