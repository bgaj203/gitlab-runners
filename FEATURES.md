# Features of GitLab HA Scaling Runner Vending Machine for AWS

**High Availability, Elastic Scaling, Spot & Windows**

# Table of Contents

[[_TOC_]]

## Scaled Runner Management Built-In

- Upgrading, Downgrading, Scaling by updating CloudFormation Stack. (e.g. Changing Instance Type, GitLab Runner Version, Scaling parameters)
- Latest AMI and/or OS Patching by updating CloudFormation Stack.
- Latest Runner Version and Version Pegging (Configurable).
- Latest AWS Prepared AMI Lookup, Custom AMI Pegging.
- GitLab Runner naming with account and instance id to facilitate finding a runner in your AWS accounts.
- AWS Tagging with GitLab Runner tags and instance URL to allow location of instance in GitLab Instance(s).

## Runner Cost Management Built-In

- Developer Self-Service through CloudFormation Direct Launch and Compatiblity with AWS Service Catalog for Enterprises.
- Flexible leveraging of spot compute.
- Configurable scheduled shutdown and/or startup for runners that do not need to run 24x7. For instance, you save 76% when a runner is scheduled for 40 hours a week ((168-40/168)=76%)

## Runner Configuration Best Practices

- GitLab Runner tagging for compute type (Spot/On Demand), OS, archtecture (if not x86_64), executor type - so that individual jobs can select on these attributes.  
- Runner tags enable pipeline engineers to ensure only mutable jobs run on spot runners.
- Shared Runner Cache per-asg is automatically configured and uses S3 object storage. Can override bucket name to share cache across multiple ASGs if it makes sense to do so.
- Runner deregistration and draining (for non-spot) during scale-in to prevent many dead tokens in GitLab.
- Runners are tagged when any AWS scaling schedule is in use - this helps everyone understand why a specific runner might go offline at certain times.

## Security

- Configurable IAM Instance Profile to avoid having to pass credentials to runner jobs.
- Least privilege when using built-in security configuration.
- Least configuration - does not configure items that are not needed to fulfill functionality indicated by configured parameters.

## High Availability

- Configurable with or without scaling.
- Warm HA of single instances via ASG respawning (downtime during respawn).
- Hot HA by using two instances.

## Elastic Scaling

- CPU or Memory metric.
- Stepped Scaling for faster response under steep workload increases.
- Many metrics beyond CPU and Memory are collected to CloudWatch to for visibility into Network, Disk IO or other bottlenecks - for specialty workloads and instance type tuning.

## Supported Combinations of Operating Systems, Runner Executors and Hardware Architectures

- Operating Systems: Windows, Linux
- Runner Executors: Docker, Shell
- Hardware Architectures: x86_64, ARM64 (Linux Only)
- Any combination of the above.

## AWS Features and Best Practices

- Defaults to Amazon Linux 2 for better density, integration and optimization (including docker optimizations).
- ASG Launching Life Cycle Hooks to enable patching and reboots for kernel patching.
- ASG Termination Monitoring and Life Cycle Hooks to enable runner deregistration and job draining (if not a spot instance).
- Mixed Instances Policy support.
- These templates can be loaded into AWS Service Catalog to be a part of your internal self-service cloud automation.
- Stackname is used in all created resources so that all related resources can be quickly identified as related.

## Extensibility, Reusability and Troubleshooting

- Easy button CloudFormation templates and parameter sets are easily used as a pattern for anyone to add their most common or desired patterns.
- Modular, overridable runner configuration scripts.
- SSM Agent installed for gaining terminal access.

# Design Heuristics

## Use Boring AWS/IaC Technology

In this case of this effort, sticking to broadly known, well proven AWS infrastructure the solution is open to much more tweaking and contributions by a very wide audience of GitLab users, but also the technical professionals helping GitLab customers in the entire Partner and Alliance ecosystem.  All of these professionals are also potential contributors due to familiar with the technologies in use. It also extends the reach to other APIs.
Some examples of leverage well proven and broadly known (boring) AWS technology:

- Using standard ASGs for scaling orchestration.
- Using EC2 instance compute.
- Using CloudFormation as the Infrastructure as Code Language (enables this to become an AWS QuickStart). Being a QuickStart exposes the code to an even vaster body of professionals for debugging, refinement and enhancement.

## Abstraction (not Elimination) of Complexity of Sophisticated Architecture

As a solution becomes more sophisticated to handle use cases well or handle more cases, it naturally becomes more complex. Instead of keeping the internal implementation simple, the user experience can be abstracted.  In the case of Infrastructure as Code tooling, this generally comes down to simplifying the number of parameters that must be considered to deploy the solution for a given purpose.  There are multiple ways to front end this template with profiles of parameters to suite specific use cases.

## Why Amazon Linux 2?

AWS has engineered Amazon Linux 2 for the maxium efficiency and server density on Ec2 and for container hosts. With the newer Linux kernel it is also able to have more optimal docker performance with the overlay2 storage driver.

The defaulting of this template does not preclude anyone from creating a custom runner configuration script for any other bistro.  Generally you want to build on the AMIs built by AWS because they tend to be optimized with at least MVNe storage drivers and ENA network drivers.

## What Instance Types?

Do not use bursty instances types (t2/t3) - **especially in testing** where your expecations will be formed - because their irradict behavior will confuse the results for what autoscaling can do - especially how responsive and smooth it might be for the given workloads.

Do use nitro instances because they have MVNe storage drivers and ENA network drivers and are automatically EBS optimized.  Use a minimum of the m5 class to gain all these benefits in a general computing instance type.  Better performance may be had if you tune your instance selection to your actual workload behaviors.

## Should I Create an AMI with the Runner Embedded?

Generally no - this creates an entire artifact release cycle in front of an already complex Infrastructure as Code stack - testing is long enough without that additional development cycle.  Additionally, you will likely have to update the runner binary (and maybe others) as soon as you boot an old AMI.  Many times automation to adequately replace software will take longer than starting with a clean machine.  Developing automation to "replace an old software package" is definitely more intense that clean slate.

### Built Upon

The baseline for this template is the Ultimate AWS ASG Kickstart and Lab Kit with Spot Support.  It has many features and attibutes to learn about Autoscaling and spot and all of that is described here: https://gitlab.com/DarwinJS/ultimate-aws-asg-lab-kit/-/blob/master/README.md - It's worth it to read through the many features.
