# Testing and Troubleshooting Guide

**GitLab HA Scaling Runner Vending Machine for AWS**

# Table of Contents

[[_TOC_]]

### Scaling Troubleshooting and Testing

#### AWS ASG Scaling Configuration Flexibility

While this template allows:

* One high and one low threshold on
* Either CPU or Memory Utilization Metrics

AWS ASG itself supports many alarms on many metrics.  Multi-metric / multi-alarm scaling can get complex and cause thrashing - if it is done is should be based on actual tested thresholds based on actual runner workloads.  For instance, perhaps scaling up on CPU > 80% and seperately Memory Util > 60% - but such a configuration should come from actual load signatures of an actual customer-like mix of runner jobs.

##### Considerations and Cautions

* Scaling down testing is the easiest - simply launch the template with a Desired Capacity of 2 and Minimum Capacity of 1 and shortly after CloudFormation completes, the ASG will start scaling down.
* By definition ASG scaling alarms for a cluster are based on a metric for all existing hosts in the cluster.
* Many metrics that can be chosen, including GitLab CI Job Queue Length, are non-deterministic to actual ASG cluster loading - this is because individual jobs can have a very wide variety of memory and cpu utilization based on what is in them and whether they docker executor is in use. While responsiveness is important, it is also important not to hyperscale a cluster that is running at 50% overall utilization.
* Jobs that are in a polling cycle (say for external status), consume a GitLab Concurrency slot - but hardly any CPU. So CPU utilization alone does not tell a whole story.
* Docker runners will have low memory pressure even if all slots are filled if the exact same container is running for more than one of the slots because the shared container memory is reused by multiple containers. So memory utilization 
* Step scaling is an AWS ASG feature that should be used to improve scale up and down responsiveness, rather than using alternative metrics.  For instance, switching to a metrix that is non-deterministic of actual ASG loading (e.g. GitLab CI Job Queue Length) may be much less efficient than a more elemental set of metrics that have proper step scaling configured for responsiveness.
* Do not run scale up utilization thresholds too high (e.g. to the levels done in managing dedicated hardware) because it will not allow for natural spikiness with individual ASG runners that receive a big job when they are at the capacity that triggers scaling.
* Concurrent job settings that are too low can prevent reaching the scale up thresholds of external metrics like CPU or Memory Utilization. In theory the **Concurrent** settings of a runner would be quite high - especially with docker - in order to allow general computing metrics to be relied upon to scale.
* Hyper-scaling of runners for things like ML Ops will be less sensitive to terminations and spotty slow jobs than to cost. Due to cost, these configurations will benefit from pushing harder - specifically giving values for concurrent that are beyond the hardware limits of the machine and creating sensitive step scaling to accomodate fast scaling.
##### Optimizations

* In this template, the CloudWatch agents have been configured to allow analysis of differences between AWS Instance Types and AMIs.  This can help reveal if a specific instance type is optimized for the purpose at hand.  For instance, a given ML Ops workload may be better on CPU optimized instances while another is better on Memory optimized - but running the workload on each, performance statistics can be compared.

### Ways To Test

* Generate Load

* Edit Scaling Alarms and Change Thresholds to match existing utilization

### Generating Load

**IMPORTANT**: DO NOT use the built in CPU stressing capability of this template because at this time it prevents proper completion of CloudFormation which eventually puts the stack into Rollback.

There is a project with a runner stressing utility here: https://gitlab.com/gitlab-org/ci-cd/gitlab-runner-stress  As with all scaled computing - please be very responsible not to run up costs by leaving scaled tests running for too long.

### TroubleShooting Guide For All The IaC Parts

**IMPORTANT**: The number one suspected cause in debugging cloud automation is "You probably are not being patient enough and waiting long enough to see the desired result." (whether waiting for automation to complete or metrics to flow or other things to trigger as designed)

  * **Linux**: Generally assumes an AWS prepared AMI (all AWS utilities installed and configured for default operation). For Amazon Linux - assumes Amazon Linux **2**. (CentOS7 Compatibile / systemd for services)
  * **Windows**: Generally assumes AWS prepared AMI (all AWS utilities installed and configured for default operation) using upgraded AWS EC2Launch client (and NOT older EC2Config) (For AWS prepared AMIs this equates to Server 2012 and later)

#### Both Operating Systems

1. Should be accessible via the SSM agent - which means zero configuration to get a command console (non-GUI on Windows) via Ec2. This obviates the need for a public address, security groups that open SSH or RDP and a Internet gateway. Use SSM for a console as follows:
  2. Right click an instance and choose "Connect"
  3. Select the "Session Manager" tab.
  4. Click "Connect".  If the button is not enabled you most likely have to wait a while until full configuration has been completed.
5. **IMPORTANT:** If you are iterating over a runner configuration script AND you are sourcing the script from a raw git url - you do NOT need to teardown the entire stack simple to test changes to this script because it is dynamically sourced during the ASG spin up of the instance.
   1. Edit the ASG and set the Desired and Minimum to zero
   2. update the script in the git repository
   3. Edit the ASG and set the Desired and Minimum counts to at least 1.

#### Linux

##### Linux Userdata (includes download and execution of runner configuraiton script)

* **Userdata Execution Log**: `cat /var/log/cloud-init-output.log`
* **Resolved Script (CF Variables Expanded)**: `cat /var/lib/cloud/instance/scripts/part-00`

##### Linux Runner Configuration

- **Rendered Custom Runner Configuration Script**: `cat /custom_instance_configuration_script.sh`

##### Linux Termination Monitoring

* **Termination Monitoring Script**: `cat /etc/cron.d/MonitorTerminationHook.sh`
* **Schedule of Termination Monitoring**: `cat /etc/crontab`

##### Linux CloudWatch Metrics

* Config file created by script (get's translated to a TOML): `cat /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json`
* Check running status: 
  * `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status`
  * `systemctl status amazon-cloudwatch-agent`
  * start: `systemctl start amazon-cloudwatch-agent`
  * stop: `systemctl stop amazon-cloudwatch-agent`
* Tail Log: `tail /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log -f`

#### Windows

##### Techniques for Non-GUI Windows Troubleshooting

* Viewing text files in the console - windows powershell has many linux aliases - so just use cat:

  `cat somefile.txt`

* Use this oneliner to install the console based text file editor 'nano' on headless windows: 

  `If (!(Test-Path env:chocolateyinstall)) {iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex} ; cinst -y nano`

* Use this oneliner to create a function to tail windows event logs in the console (similar to `tail -f /var/log/messages`):

  `Function Tail ($logspec="Application",$pastmins=5,[switch]$f,$computer=$env:computername) {$lastdate=$(Get-date).addminutes(-$pastmins); Do {$newdate=get-date;get-winevent $logspec -ComputerName $computer -ea 0 | ? {$_.TimeCreated -ge $lastdate -AND $_.TimeCreated -le $newdate} | Sort-Object TimeCreated;$lastdate=$newdate;start-sleep -milliseconds 330} while ($f)}; Tail`

  Tail takes positional parameters the first one is a log spec which can contain a comma seperated list and wildcards like this (for Appliation and Security logs for the last 10 minutes and waiting for more):

  `Tail Applica\*,Securi\* 10`

  Note: This is useful for tailing the Application log to watch whether the termination script is processing as desired.

##### Windows Userdata

* **Userdata Execution Log**: `cat C:\programdata\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log`
* **Resolved Script (CF Variables Expanded)**: `cat C:\Windows\TEMP\UserScript.ps1`

##### Windows Runner Configuration

* **Rendered Custom Runner Configuration Script**: `cat $env:public\custom_instance_configuration_script.ps1`

##### Windows Termination Monitoring

* **Termination Monitoring Script**: `cat $env:public\MonitorTerminationHook.ps1`
* **Schedule of Termination Monitoring**: `schtasks /query /TN MonitorTerminationHook.ps1`

##### Windows CloudWatch Metrics

* Config file created by script (get's translated to a TOML and deleted - so if it is actually here that is a problem): `cat $env:ProgramFiles\Amazon\AmazonCloudWatchAgent\config.json`
* Check running status: 
  * `sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status`
  * `systemctl status amazon-cloudwatch-agent`
  * start: `systemctl start amazon-cloudwatch-agent`
  * stop: `systemctl stop amazon-cloudwatch-agent`
* Tail operational Log: `cat C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs\amazon-cloudwatch-agent.log`
* Configuraiton validation log: `cat C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs\configuration-validation.log`