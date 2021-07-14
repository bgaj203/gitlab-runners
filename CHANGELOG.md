# Changelog

All notable changes to this project will be documented in this file.

## [v1.4.9-alpha14] - 2021-07-DD

- Spot instances use instance metadata for termination checking due to higher rate limits than ASG based checking.
- 5ASGSelfMonitorTerminationInterval is now only for non-spot termination monitoring - so it can be 5 minutes or longer.
- spot instances are always checked twice a minute for terminations.
## [v1.4.8-alpha13] - 2021-09-18

- All easy buttons and the main cloud formation template maintain internal version pegging via source pointers even when 'main' matches the most recent version.
- arm64 specific install of SSM agent and AWS CLI 2 (was not completing CF signals)
- extended ASG resource creation timeout to allow for larger initial ASG creations
- linux runner install fixes (especially shell runner)
- duplicate concurrent jobs parameter in both scaling and GitLab runner sections of CF form
- four instance types required for spot only easy buttons - this is to reduce terminations along with 'capacity-optimized-prioritized'. Selecting instances that all have the same size name will ensure similar costs. Selecting instances that all have the same size name will ensure similar costs.
## [v1.4.7-alpha12] - 2021-05-14

- As per AWS Spot team recommendations: 5SPOTSpotAllocationStrategy now defaults to 'capacity-optimized-prioritized' 
- Replaced single ARM64 Easy button with two that mimic the Linux ones where the user can provide the number of instances to obtain Warm HA, Hot HA or scaling.
- Forced 5ASGSelfMonitorTerminationInterval to lowest value (currently 1) for any easy button containing spot instances rather than rely on default value in the template

## [v1.4.6-alpha11] - 2021-04-22

- Surfaced parameters for better control of large scale updates:   4ASGUpdateMinInstancesInService and 4ASGUpdateMaxBatchSize
- Upped maximum initially deployable instances to 20 (update your CF stack to push this higher after deployment)
- In [README.md](./README.md), added documentation section **GitLab Runners on AWS Spot Best Practices**
- In [README.md](./README.md), added a link to video: [Provisioning 100 GitLab Spot Runners on AWS in Less Than 10 Minutes Using Less Than 10 Clicks + Updating 100 Spot Runners in 10 Minutes](https://youtu.be/EW4RJv5zW4U)

## [v1.4.5-alpha10] - 2021-04-19

- Simplification of number of easy buttons provided.  Consolidated all manual scaling options and scheduling on per-platform and per-spot basis. Users pick 1, 2, or more instances to control Warm HA, Hot HA or Manual Scaled Fleet. Instance count can be tuned via ASG parameter edits after deployment.
- Add preflight end-to-end connection tests for endpoints needed for successful installation and configuration of the runner. Fail immediately if there is a possible network problem between the runner network context and the GitLab instance network context. Should cover VPC config, VPC gateway configs, security group configs, NACLs, routing tables, firewalls for both the runner network location and the target GitLab Instance network location.
- Use Windows 2019 instead of 1903.
- Retry installations for AWS CLI for MSI error 1618 (MSI is processing another package).
- Reboot behavior changed to support just one reboot while in launching lifecycle hook - to simplify idempotency checks in spin up automation.
- Fix for Windows spot draining code.
- Fail immediately if instance configuration script has non-zero exit.
- Fixed "known problem: Windows machines are not completing autoscaling." noted in release v1.4.1-alpha7.

## [v1.4.3-alpha9] - 2021-03-22

- Enable a much better form based experience without oddly named parameters using AWS::CloudFormation::Interface (#23)

## [v1.4.2-alpha8] - 2021-03-17

- Enable specifying VPC with a new parameter (4ASGSpecifyVPC).  Defaults to DefaultVPC and functions identically to last version when VPC is not specified.  ASG configures for all available subnets in the VPC.
- Enable specifying VPC was implemented using a best practice CloudFormation Custom Resource python lambda function.
- LowerCase Custom function also adds 5 random alphanumeric characters
- Default branch is now 'main'
## [v1.4.2-alpha7] - 2021-03-09

- added easy button for linux docker single instance warm HA with scheduling ability
## [v1.4.1-alpha7] - 2021-03-06

- spot terminations no longer attempt to drain jobs - there is no time for that - all jobs running on spot should be mutable (#1)
- added asg permission autoscaling:UpdateAutoScalingGroup to enable runner and runner jobs to use the aws cli to take scaling actions for the ASG of the runner for predictive or specific scaling (#13)
- known problem: Windows machines are not completing autoscaling.

## [v1.4.1-alpha6] - 2021-03-05

- Easy Button Parent CF Templates for one button click - compatible with QuickStarts and AWS Service Catalog
- added CF custom resource for lowercase to ensure bucketname is always lowercase
- Renamed parameters from SPOTInstanceType to ASGInstanceType to avoid confusion for non-spot and mixed instances implementations
- Renamed 1OSPatchRunDate to 1OSLastManagedUpdate
- Simplification of README.md by breaking out FEATURES.md

## [v1.4.0-alpha6] - 2021-02-02

- Support for arm64 architecture for Amazon Linux 2
## [v1.4.0-alpha5] - 2021-02-02

- Automatically configures a Shared S3 Cache (#8)
- Removed option for installing SSM Agent - just always install it. (#10)
- Removed CodeDeploy option leftover from ASG template.  SSM Agent can perform "in-place" updates if they need to be used instead of simply doing a rolling replacement of instances using an CF Stack update. (#9)
- Enable a list of runner registration tokens for Linx (#2)
- Add "NoEcho" to parameter for runner token
- Semicolon delimiting of runner token list to prevent CF parameter problems
- Easy Button Parameter Set Examples (#11)
  
## [v1.4.0-alpha4] - 2021-01-28

- This is really a **first MVP** release - will need everyone's help to refine.
- Rename to GitLab Scaling Runner Vending Machine for AWS
- removed default parameters for autoscaling scaling because we do not currently have a tested and advised default for general runner deployment
- updated template parameter names and help text
- enablement video added to readme
- first release ready for external testing
- four runner configs working
- added memory and other instance metrics via cloudwatch
- memory utilization scaling for Linux

## [v1.4.0-alpha3] - 2021-01-27

- first release ready for external testing
- four runner configs working
- added memory and other instance metrics via cloudwatch
- memory utilization scaling for Linux

## [1.3.1] - 2020-05-20

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
