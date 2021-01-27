# GitLab Runner Autoscaling on AWS with Spot

The baseline for this template is the Ultimate AWS ASG Kickstart and Lab Kit with Spot Support.  It has many features and attibutes to learn about Autoscaling and spot and all of that is described here: https://gitlab.com/DarwinJS/ultimate-aws-asg-lab-kit/-/blob/master/README.md - It's worth it to read through the many features.

### Scaling Testing
- Scaling down testing is the easiest - simply launch the template with a Desired Capacity of 2 and Minimum Capacity of 1 and shortly after CloudFormation completes, the ASG will start scaling down.

### The Runner Part

Runner Specific or Highlighted Features:
- Start / Stop ASG schedule - specify a cron expression for when the cluster scales to 0 for Min and Desired (stop schedule) and when it scales to "Min=1" "Desired=<yourvalue> " (start schedule), after which autoscaling takes over.
- Runner information tagged in AWS and instance name and AWS account set as runner name for easy mapping of runners in GitLab to instances in AWS and vice versa.
- Runners self-tag as computetype-spot or computetype-ondemand to allow GitLab CI job level routing based on this information.
- Runners self-tag with gitlab runner executor type

Each runner supported as a bash or powershell script in the "runner_configs" directory. The parameter that take these scripts can be point to any available URL. When pointing it to GitLab, be sure to use a full raw URL that is accessible directly from your instance as it spins up in AWS.

These are then referenced in the primary Cloud Formation template in the CloudFormation parameter 3INSTConfigurationScript.

Currently the windows one is the most developed (because scaling shell runners is a need).

Note that these runner scripts have the following attributes (when fully completed):
* They are pulled dynamically by instances that are scaling - so they cannot use CloudFormation variable substitutions because that is done long before these are pulled and used.
* They must overwrite the TerminationMonitor script built into the CF template so that they can properly drain and unregister a runner on a scale-in operation.
* They rely on variable pass through from the main cloud formation code
* For runners with docker, the user should just provide an AWS prepared Amazon Linux 2 or Windows AMI with docker preinstalled in parameter
* They follow the best practice of using AWS ASG lifecycle hooks to give the instance time to be built - but more importantly, to allow it to drain and unregister on scale-in.
* They name and tag runners in both AWS and GitLab to ensure easy cross-system identification.

### Should I bother using this scaled runner template for Docker-machine since it has scaling built in?

Yes - because:
* By having your entire runner build in an ASG you are making your runner provisioning production-grade because it is IaC (built with code)
* When you end up with runner sprawl, the prospect of updating all runners is much less daunting if they are all built with IaC
* the dispatcher node should be in a single instance ASG for warm HA (respawn on death).  
* It benefits from all the other features of this template including maintenance by repulling the latest AMI, latest patches and latest runner version upon a simple CF stack update.
* Docker-machine should be able to be completely replaced by a well tuned ASG housing the plain docker executor.

### TroubleShooting Guide

**IMPORTANT**: The number one suspected cause in debugging cloud automation is "You probably are not being patient enough and waiting long enough to see the desired result." (whether waiting for automation to complete or metrics to flow or other things to trigger as designed)

  * **Linux**: Generally assumes an AWS prepared AMI (all AWS utilities installed and configured for default operation). For Amazon Linux - assumes Amazon Linux **2**. (CentOS7 Compatibile / systemd for services)
  * **Windows**: Generally assumes AWS prepared AMI (all AWS utilities installed and configured for default operation) using upgraded AWS EC2Launch client (and NOT older EC2Config) (For AWS prepared AMIs this equates to Server 2012 and later)

#### Both Operating Systems
* Should be accessible via the SSM agent - which means zero configuration to get a command console (non-GUI on Windows) via Ec2. This obviates the need for a public address, security groups that open SSH or RDP and a Internet gateway. Use SSM for a console as follows:
  1. Right click an instance and choose "Connect"
  2. Select the "Session Manager" tab.
  3. Click "Connect".  If the button is not enabled you most likely have to wait a while until full configuration has been completed.
#### Linux
##### Linux Userdata (includes download and execution of runner configuraiton script)
* **Resolved Script**: 
* **Userdata Execution Log**: `cat /var/log/cloud-init-output.log`

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
* Use this oneliner to install the console based text file editor 'nano' on headless windows: 
  
  `If (!(Test-Path env:chocolateyinstall)) {iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex} ; cinst -y nano`

* Use this oneliner to create a function to tail windows event logs in the console (similar to `tail -f /var/log/messages`):

  `Function Tail ($logspec="Application",$pastmins=5,[switch]$f,$computer=$env:computername) {$lastdate=$(Get-date).addminutes(-$pastmins); Do {$newdate=get-date;get-winevent $logspec -ComputerName $computer -ea 0 | ? {$_.TimeCreated -ge $lastdate -AND $_.TimeCreated -le $newdate} | Sort-Object TimeCreated;$lastdate=$newdate;start-sleep -milliseconds 330} while ($f)}; Tail`
  
  Tail takes positional parameters the first one is a log spec which can contain a comma seperated list and wildcards like this (for Appliation and Security logs for the last 10 minutes and waiting for more):
  
  `Tail Applica\*,Securi\* 10`
  
  Note: This is useful for tailing the Application log to watch whether the termination script is processing as desired.

##### Windows Userdata
* **Resolved Script**: `cat C:\Windows\TEMP\UserScript.ps1`
* **Userdata Execution Log**: `cat C:\programdata\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log`
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

### Scaling Troubleshooting and Testing

**IMPORTANT**: DO NOT use the built in CPU stressing capability of this template because at this time it prevents proper completion of CloudFormation which eventually puts the stack into Rollback.
#### CloudWatch Scaling
Alarms are not simple thresholds, they must be **breached* to enact the associated scaling rule.  For instance if your CPU utilization low threshold is 20% and your ASG starts and never goes above 20%, scale down will not occur because the alarm was not breached - the utilization simply never was above the threshold.

#### AWS ASG Scaling Configuration Flexibility

While this template allows:

* One high and one low threshold on
* Either CPU or Memory Utilization Metrics

AWS ASG itself supports many alarms on many metrics.  Multi-metric / multi-alarm scaling can get complex and cause thrashing - if it is done is should be based on actual tested thresholds based on actual runner workloads.  For instance, perhaps scaling up on CPU > 80% and seperately Memory Util > 60% - but such a configuration should come from actual load signatures of an actual customer-like mix of runner jobs.

##### Considerations and Cautions

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

#### Ways To Test

* Generate Load
* Edit Scaling Alarms and Change Thresholds