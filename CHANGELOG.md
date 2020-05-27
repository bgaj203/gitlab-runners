# Changelog
All notable changes to this project will be documented in this file.

## [2.3.0] - 2020-05-20
### Updated
- Sync code with Ultimate ASG Kickstart Version 1.3.0 - especially to enable runner and AWS tagging of "spot" versus "ondemand" runner instances.

## [1.3.0] - 2020-04-17
### Added (from Ultimate ASG Kickstart and Lab Kit)
- Instances tag themselves as spot or on-demand.  Tag is COMPUTETYPE=SPOT or COMPUTETYPE=ONDEMAND
- Template defaults to 100% spot instances, disable spot by updating parameter 5SPOTOnDemandPercentageAboveBaseCapacity=100
- Permission an s3 bucket to support CodeDeploy and SSM, provide an existing bucket or have the template create one for you.
- autocreated bucket name includes CF stack name - so stack name must be all lower case if using the autocreated bucket.
- Now Demonstrates use of "Rules:" for cross parameter valid to prevent using the default linux ami with a windows stack.
- Rather than the previous version behavior of a) conditional creation of, b) inline policies - a) always creates b) Managed Policies (named per-stack).  This makes it easier to both understand the minimum permissions and attach them to existing roles.
- Optional keypair for logon through SSH client or Ec2 web SSH
- Most resource name uniqueness is accomplished via starting with ${AWS::Stackname}
- Name change to add "Kickstart" to indicate this is suitable for both getting started quickly for the first time in ASG and/or spot as well as suitable for starting new projects even if you are familiar with implementing these.

## [1.2.0] - 2020-03-24
### Added
- Added the ability to download and execute an extension to Userdata from a embedded (no download), local file (no download), s3://, https:// or http://

## [1.1.0] - 2020-03-23
### Added
- First version, updates described in [README.md](README.md)