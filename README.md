# Ultimate AWS ASG Lab Kit with Spot Support

A while back I wrote a blog and companion Cloud Formation templates for experimenting with the ways an ELB creation template could be linked to an ASG.  That iteration was based on an ASG template designed to show how to kernel patch linux and reboot without termination using ASG Lifecycle hooks.

I had a number of improvements I wanted to make to this template set and this blog represents that work.

The result is really the answer to the question "What would be have been a simple, but production-useful working example to learn the things needed to experiement with AWS ASGs that leverage spot instances and proper lifecycle hooks?"

Since the last team I managed had to do all of our automation work for both Windows and Linux, I wanted the solution to work for both.

<!--more-->
<!-- TOC -->

- [TL;DR Feature Summary](#tldr-feature-summary)
  - [Previously Existing Features](#previously-existing-features)
  - [New Features (all for both Windows and Linux):](#new-features-all-for-both-windows-and-linux)
- [Technical Design](#technical-design)
  - [Minimal but Completely Working Template](#minimal-but-completely-working-template)
  - [Tested With Both ASG Updatepolicy Settings](#tested-with-both-asg-updatepolicy-settings)
  - [Least Privilege IAM](#least-privilege-iam)
  - [Maximizing ARN Flexibility for Template Reuse](#maximizing-arn-flexibility-for-template-reuse)
  - [Works Without ASG](#works-without-asg)
  - [Patch Maintenance Built-in](#patch-maintenance-built-in)
  - [Scheduled ASG Patching](#scheduled-asg-patching)
  - [Scheduling Instance Availability](#scheduling-instance-availability)
  - [Monitoring and Metrics](#monitoring-and-metrics)
    - [LAST_CF_PATCH_RUN](#lastcfpatchrun)
    - [ACTUAL_PATCH_DATE](#actualpatchdate)
- [Testing and Observing](#testing-and-observing)
  - [Kicking Off The Template](#kicking-off-the-template)
  - [Testing Scaling Configuration with Synthetic CPU Loading](#testing-scaling-configuration-with-synthetic-cpu-loading)
  - [Observing Lifecycle Hooks in AWS Console](#observing-lifecycle-hooks-in-aws-console)
  - [Observing On Instance Script Actions](#observing-on-instance-script-actions)
  - [Observing Logs on The Instance](#observing-logs-on-the-instance)
  - [Observing Pseudo Web App](#observing-pseudo-web-app)
- [Code for This Post](#code-for-this-post)
- [Nitty Gritty Appendix: Architecture Heuristics: Requirements, Constraints, Desirements, Serendipities, Applicability, Limitations and Alternatives](#nitty-gritty-appendix-architecture-heuristics-requirements-constraints-desirements-serendipities-applicability-limitations-and-alternatives)

<!-- /TOC -->

# TL;DR Feature Summary

So here is the net set of functionality that the Ulitimate AWS AutoScaling Group Lab Kit includes:

### Previously Existing Features

The following features were made available in a previous incarnation of this template at: https://cloudywindows.io/post/asg-lifecycle-hook-for-linux-kernel-patching-with-a-reboot-in-aws-autoscaling-groups/

* [x] Create a "Launching" ASG lifecycle hook so Linux kernel patching could reboot before health checks start (thereby avoiding early termination).
* [x] Allow an test web app to be installed to emulate a real application server.
* [x] Maintainability Built-in: Enable patch updating of the cluster by simply updating the CloudFormation stack.
* [x] Optional Troubleshooting mode that sets up SSM permissions and installs the SSM agent.
* [x] Support High Availability Only (no scaling): Warm HA (1 Instance - usable for applications that don't support multiple nodes), HOT/HOT HA (2 instance ASG - if application supports it)
* [x] "logit" function to expose script information to the console and common logs (Linux: /var/log/messages, Windows: Application log

Here is the previous article if you want to learn more about it's features and design - which includes comparison to other ASG patching methods: [ASG Lifecycle Hook for Linux Kernel Patching with a Reboot In AWS Autoscaling Groups](https://cloudywindows.io/post/asg-lifecycle-hook-for-linux-kernel-patching-with-a-reboot-in-aws-autoscaling-groups/)

### New Features (all for both Windows and Linux):

* [x] Be a great lab kit for learning, but also be a **great starting point for actual production implementations**.
* [x] **Windows support** for all previous functionality which was only for Linux. This is especially important if your Windows spin up and initial automation might exceed the default hook time of 60 minutes (ahhh, and time to make a custom AMI for that and to never use T2 instances - just saying)
* [x] Maintainability Built-in: Allow CloudFormation to **lookup the latest AMI** (including on updates) AND enable an override to peg to a specific or custom AMI.
* [x] **Optional installation of CodeDeploy** in case the ASG is wired to it for code deployment.
* [x] **Group CloudFormation parameters** in a sensible way, rather than the default alphanumeric sort.
* [x] Support "**Least Resource Creation**" by only creating AWS resources when they will be used - for instance not configuring SSM IAM permissions if the troubleshooting feature was not configured.
* [x] Support **Spot Instances** and basic spot configuration parameters.
* [x] Support **non-Spot configurations** (by setting On Demand Percentage Above Base to zero) - which also supports complete on-demand ASGs that can select from multiple instance types to avoid failure when a specific instance is exhausted in an availability zone.
* [x] Support **Configurable Autoscaling (optional)** and include parameters for configuring it (step scaling policies)
* [x] Support **TERMINATING lifecycle hooks** and cleanup script for implementations that should do clean up or deregistration when the ASG scales in.
* [x] Support **three OS Patch Scopes**: all patches, only security patches and no patching (for faster testing of other things)
* [x] **State based installs** - only trigger installs if the desired software is not present already.
* [x] **Built-in scaling testing** by including an optional sythentic CPU driving utility and SSM parameter to control it. This allows you to dial-in the CPU utilization load you want the ASG to be under and change it after deployment to completely validate the scaling parameters and smoothness. Following the "Least Resource Creation" principle, the resources to support this are only deployed if you configure the capability.
* [x] **Allow override of the basic, built-in Instance Profile IAM Role** that the template creates with one that already exists.


# Technical Design

## Minimal but Completely Working Template

The CloudFormation template is purposely minimal in order to more clearly demonstrate the concepts of the solution.  At the same time it includes everything needed and works.  The approach adheres to [The Testable Reference Pattern Manifesto](https://cloudywindows.io/post/back-to-basics-testable-reference-pattern-manifesto-with-testable-sample-code/)

## Tested With Both ASG Updatepolicy Settings

The parameter UpdateType defaults to "RollingThroughInstances" which sets the UpdatePolicy to use AutoScalingRollingUpdate, but it can be changed to "ReplaceEntireASG" to set the UpdatePolicy to use AutoScalingReplacingUpdate.  Although not tested with Lambda based updates, they would be expected to work just fine with this template.

## Least Privilege IAM

The IAM Roles and least privilege permissions are included so that it is clear what permissions are needed and so that instances do not have more permissions than needed to interact with their own ASG.  Two possible methods for limiting the permissions are provided. Using the ASG name in the Resource specification of the IAM is active.  Using a condition on a tag is provided as a tested, but commented out alternative.

## Maximizing ARN Flexibility for Template Reuse

The ASG arn in the IAM policy with the SID "ASGSelfAccessPolicy" demostrates maximizing the use of intrinsic AWS variables by using them for **AWS Partition** (use in Gov cloud or China without modification), **AWS Account ID** (use in any account) and **AWS Region** (use in any region without modification).

## Works Without ASG

If the userdata code cannot retrieve it's ASG tag it assumes that it is not in an ASG and all lifecycle hook actions are skipped.  This allows the solution to be used in non-ASG scenarios.

## Patch Maintenance Built-in

Zero-downtime patching for the entire ASG is supported by updating the PatchRunDate in the cloudformation stack - the entire fleet will be replaced with instances that are up to date on patching.  The date is purposedly used to record an environment variable within Userdata so that the ASG Updatepolicy knows it should replace all instances.

## Scheduled ASG Patching

By simply scheduling a cloud formation update command with an updated date, the entire ASG will roll. The most AWS cloudy way to do this is a scheduled CloudWatch Event that triggers a Lambda function.

```
aws cloudformation update-stack --stack-name "your-asg-stack" --parameters ParameterKey=1OSPatchRunDate,ParameterValue=$(date '+%Y-%m-%d'),UsePreviousValue=false
```

## Scheduling Instance Availability

If you are using this template primarily for HA for an instance, you can also consider using skeddly to set the ASG Desired and Minimum counts to zero for the hours that the instance will not be in use.  This assumes that the installed software has it's state data somewhere else and that you use the termination monitoring to perform any orderly application shutdown if it is needed.

## Monitoring and Metrics

Two monitoring and metrics values are recorded as metadata.  You can control what log file the is added to (or mute the log file) by altering the function "logit".  Generally you want this to be a log file that is collected by your log aggregation service (sumologic, loggly, etc).  If you already collect /var/log/cloud-init-output.log, you can mute the log file write to /var/log/messages.

### LAST_CF_PATCH_RUN

The CloudFormation parameter `PatchRunDate` is:

  * saved on the instance as the environment variable LAST_CF_PATCH_RUN in /etc/profile.d/lastpatchingdata.sh
  * emited to /var/log/messages as "LAST_CF_PATCH_RUN: <datavalue>"
  * added as a tag to both the ASG and all Ec2 instances

This date simply indicates the initial setup of the ASG or the last fleetwide forced patch.  It also serves to purposely change something in userdata so that the entire fleet is forced to be replaced when you run an update and change this date.

### ACTUAL_PATCH_DATE

The date as of spin-up is:

  * saved on the instance as the environment variable ACTUAL_PATCH_DATE in /etc/profile.d/lastpatchingdata.sh emited to /var/log/messages as "ACTUAL_PATCH_DATE: <currentdate>"

Instances that spin up as a result of autoscaling will not have their patches limited to the date expressed in LAST_CF_PATCH_RUN, so ACTUAL_PATCH_DATE tracks the date they were actually patched.

Comparing these two dates can help you understand if you have developed a large variety of patching dates due to autoscaling and might want to roll the fleet to a standard date by updating the cloudformation with a new `PatchRunDate`.

# Testing and Observing

## Kicking Off The Template

Use the AWS CloudFormation console to launch the template - to see how subsequent updates will work, pick 4 instances and set TroubleShootingMode to true.

## Testing Scaling Configuration with Synthetic CPU Loading

You can validate whether the following respond as designed:

* Verify designed scaling responsiveness and smoothness - up and down.
* Verify AZ scaling configuration.
* Verify Spot / On-demand instance parameters are responded as designed including instance types, mixed instances policy, percentage spot, etc.

During deployment, be sure to enter a numeric value for the **8DBGCPULoadPercentInitialValue** parameter (Yeah sorry, I even like my variable names to be fully self documenting).

If you do not want scaling to occur immediately, set it low to something like 5.

If you do not provide a value at all, Synthetic CPU Loading is not even setup because this template follows a principle of "Least Configuration".

After the template completes, you will find a new SSM parameter that is named as "**YourASGName-SyntheticCPULoad**" as the parameter name.  Since the ASG name is dynamically named it will be prepended with some random characters.

You can now vary the synthetic CPU load using the parameter and watch the CloudWatch alarms for scale out and scale in and watch the AutoScaling Group for scaling actions.

> **IMPORTANT!**  Do not deploy the template with a value that causes scale out and then forget about it for a long period or overnight - you might bankrupt your company with AWS billing charges.

## Observing Lifecycle Hooks in AWS Console

In the EC2 Console open the Autoscaling group, on the "Lifecycle Hook" tab observe the 'instance-patching-reboot' hook is configured.

Also, before the instances are in service you can see "Not yet in service" in the "Activity History" tab and "Pending:wait" in the "Lifecycle" column of the "Instances" tab for each instance.  These will change to indicate the instances are in service as each instance completes setup procedures.

The same is true for observing the terminating hook.

## Observing On Instance Script Actions

All the actions of this template can be observed without logging into the instance by using the AWS console to view the system log for instances (Right Click Instance => Instance Settings => Get System Log) and scanning for the text "USERDATA_SCRIPT:"  

The first message will contain "Processing userdata script on instance:".  All the messsages include timestamps so that you can observe things like how long a reboot took and the fact that if you don't sleep the script, it keeps processing for a while after the reboot command.

On Windows you would need to retreive the Application log to watch launching and terminating hook actions.

If you enable the debugging mode you can get a web based console prompt on both operating systems using SSM Session Manager console.

## Observing Logs on The Instance

If you need or want to logon to the instance for examination or troubleshooting, set the parameter `TroubleShootingMode` to 'true'.  This enables SSM IAM permissions and installs the SSM agent on the instances to allow AWS Session Manager to logon using SSH or WinRM. 
For linux, the log lines that you see in the AWS System Console will be in the CloudFormation log at: \var\log\cloud-init-output.log. For Windows it will be the Application log.
For observing the termination hook SSM will leave the last received log on the screen - so you can actually see the termination messages after the instance is gone.
On Linux you can use:

```bash
tail -f /var/log/messages
```

On Windows you can use (it is also a good generic EventLog tailing function):

```powershell
Function TailLog ($logspec="Application",$ms=330) {while ($True) {$newdate=get-date;get-winevent $logspec -ea 0 | ? {$_.TimeCreated -ge $lastdate -AND $_.TimeCreated -le $newda
te};$lastdate=$newdate;start-sleep -milliseconds $ms}}; TailLog
```

## Observing Pseudo Web App

If you set SetupPseudoWebApp to true, the following is done: 1) A port 80 ingress is added to the default VPC security group, 2) Apache is installed, 3) an apache home page is created which publishes the patching and ASG details of the

# Code for This Post

[CloudFormationRebootRequiredPatchinginASG.yaml](https://github.com/DarwinJS/DevOpsAutomationCode/blob/master/CloudFormationRebootRequiredPatchinginASG.yaml)

[Create Now in CloudFormation Console](https://us-east-1.console.aws.amazon.com/cloudformation/home?region=us-east-1#/stacks/create/review?templateURL=https://s3.amazonaws.com/cloudywindows.io/files/CloudFormationRebootRequiredPatchinginASG.yaml)

# Nitty Gritty Appendix: Architecture Heuristics: Requirements, Constraints, Desirements, Serendipities, Applicability, Limitations and Alternatives

This section details some of the complex journey that goes into creating a simple and highly functional pattern. It is most helpful to those who would like to architect on top of this solution.

I find it very helpful to enumerate architecture heuristics of a pattern as it helps with:

```
1. keeping track of the architecture that emerged from the 'design by building' effort.
2. my own recollection of the value of a pattern when examining past things I've done for a new solution.
3. others quickly understanding the all the points of value of an offered solution - helping guide whether they want to invest in learning how it works.
4. facilitating customization or refactoring of the code by distinguishing purpose designed elements versus incidental elements.
```

I specifically like the model of using **Constraints, Requirements, Desirements, Applicability, Limitations and Alternatives** as it helps indicate the optimization of the result without stating everything as a "requirement". This model is also more open to emergent architecture elements that come from the build effort itself.

 - **Requirement: (Satisfied)** Idempotent coding - does not assume anything about the installed / configured state of a given item. This includes elemental automation utilities like AWS CLI.  This allows the code to work:
    - On a broader set of distros / editions.
    - On an AMI that has been prepared from scratch without standard AWS tooling.
    - With multiple pass processing when an instance is rebooted (already performed steps are skipped or result in no changes).
 - **Requirement: (Satisfied)** Support both Windows and Linux (yum packaging) in all functionality.
 - **Requirement: (Satisfied)** Handle full patching or just security patching.
 - **Requirement: (Satisfied)** Support spot instances.
 - **Requirement: (Satisfied)** Unique internal naming tied to stack name so that it can be deployed many times for multiple, parallel deployments.
 - **Requirement: (Satisfied)** Least Resource Creation - only create AWS resources or do instance installs if they will be used by the specific template launch. (e.g. Providing an IAM Instance Profile Role disables the built-in role creation)
 - **Requirement: (Satisfied)** Support terminating lifecycle hooks to trigger cleanup / deregister during scale in.
 - **Requirement: (Satisfied)** State Based Reboot - only reboot if reboot detection code shows that it is actually needed.
 - **Requirement: (Satisfied)** Precompile .NET bytecode after patching to ensure that new and patched .NET assemblies do not slow down production operations.
 - **Desirement: (Satisfied)** Write code in lowest common denominator so it can be wrapped in other orchestrators.  Hence this is done in CloudFormation, which can be encapsulated into other automation systems.
 - **Desirement: (Satisfied)** Built-in scaling testing through driving synthetic CPU load across all instances in the ASG with the capability to change it on demand.
 - **Desirement: (Satisfied)** Organize CloudFormation parameters in groups to make a more sensible interactive template deployment experience.
 - **Desirement: (Satisfied)** Self-documentation by exposing all help  information as CloudFormation parameter descriptions - increasing usability for both interactive use and automated use via integration of documentation as comments.
 - **Desirement: (Satisfied)** Build in ASG scaling testing for learning and for production configuration validation.
 - **Desirement: (Satisfied)** Allow IAM Instance Profile Role override with external role
 - **Desirement: (Satisfied)** Automatic latest AWS built AMI lookup with override to peg the AMI.
 - **Desirement: (Satisfied)** Support Gov ARNs without code modification.
 - **Desirement: (NOT Satisfied)** It would be nice if the solution could work with a fixed patch baseline to allow full DevOps environment promotion methods using a known, version pegged set of patches.
 - **Limitation:** The patch level is dynamic and not a fixed baseline. When scaling occurs the newest instances will have patching up to date with their spin-up date.  These newer patches will not have been tested with the application.
   - **Countermeasure**: If you integrate automated QA testing with the provisioning of a new instance, you could catch problems with patching when they happen or by running a separate nightly build of the server tier againt the latest patches.
 - **Limitation:** If you need to design for multiple or many reboots, you would have to do custom code to ensure userdata could pick up in the proper spot after each reboot.
   - **Countermeasure**: This situation is exactly what cfn-init is for, if you have not previously used it, you can read up on how to implement it **within** the pattern in this post.
- **Applicability:** If you already release a per-ASG AMI for your own reasons (usually speed of scaling), then simply ensuring that AMI takes into account your desired patching frequency is a better solution.  You could shorten your AMI release cycle to something like monthly so that satisfactory patching happens as part of the existing release process.  This has the side benefit of version pegging your patching level and allowing it to be part of your development and automated QA and be ensured that production runs on a tested patch level.
  - **Alternative:** If you have an existing long AMI release cycle (greater than 6 months), you could combine it with the dynamic patching solution offered here to keep the cycle long (to keep the cost and logistics of managing old AMIs to a minimum if that is a high priority).
- **Alternative: Critical Vulnerability Response** If you have an urgent enough patching scenario, you may wish to temporarily use this pattern to do dynamic patching when you do not normally support it.
- **Limitation:** This demo template relies on the default VPC security group being added to the instances and on it having default settings which allow internet access.  If you have the default VPC security group nulled out (a great security practice!) or other networking configuration that limits internet access, you will need to update the template so that it has outbound internet access in your environment.

