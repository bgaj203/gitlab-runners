# Ultimate AWS ASG Lab Kit with Spot Support

## Operating System
* All features work both Linux (yum packaging) and Windows using the same CloudFormation template
* Run security updates - select all updates or only security (win/lin)
* install basic utils for non-AWS AMIs (aws cli, pip, cfn-bootstrap)

## ASG and HA Features
* Spot support (or On-Demand Fleet)
* ASG Lifecycle Hook for provisioning - to support patching, software install and rebooting before placing into InService and heath checks occur
* ASG Lifecycle Hook for deprovisioning during termination
* Pseudo HA by ASG Respawn (1 node ASG)
* True HOT/HOT HA (at least 2 nodes)
* Optional autoscaling enablement
* Control over scaling parameters
* Control over spot parameters
* Use an existing InstanceProfile or the minimal one included

## Tooling Features
* Good starting point for production templates
* Pure CloudFormation - wrap it in whatever you like (e.g. TerraForm)
* Help as parameter descriptions - can figure out how to use it by just loading it in cloudformation console and reading the description in each parameter.  Parameters are also properly grouped by their function.
* Deploy many times - resource naming is auto generated so there are no name clashes when reusing the template multiple times
* CloudFormation Debugging support (One-button SSM Session Manager Enablement)
* logit function logs to common locations on a per-platform basis (/var/log/messages and Windows Application log)
* Latest AWS AMI Lookup for your platform (linux or Windows) or peg to a specific AMI
* Least AWS resources creation - only creates AWS stuff if you've configured it to be used

## Scaling Testing
* Built in scaling and spot strategy live testing.  Optional SSM Parameter that controls synthetic CPU loading for the entire ASG so you can actually test your scaling settings by dialing the precise cluster CPU load. 
  You can validate whether the following respond as designed:
  * Verify designed scaling responsiveness and smoothness - up and down.
  * Verify AZ scaling configuration.
  * Verify Spot / On-demand instance parameters are responded as designed including instance types, mixed instances policy, percentage spot, etc.

## Maintenance Built-In
* To bring the entire ASG up to the latest AMI and patch it - simply update the cloud formation stack and just put todays date in the parameter "1OSPatchRunDate" - a rolling update will be performed on the ASG.  You should be running at least two instances for zero downtime updates.
* Setup skeddly to set the ASG Desired and Minimum counts to "0" when you don't need the runner to be available.