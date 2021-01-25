# GitLab Runner Autoscaling on AWS with Spot

The baseline for this template is the Ultimate AWS ASG Kickstart and Lab Kit with Spot Support.  It has many features and attibutes to learn about Autoscaling and spot and all of that is described here: https://gitlab.com/DarwinJS/ultimate-aws-asg-lab-kit/-/blob/master/README.md - It's worth it to read through the many features.

### Scaling Testing
- Scaling down testing is the easiest - simply launch the template with a Desired Capacity of 2 and Minimum Capacity of 1 and shortly after CloudFormation completes, the ASG will start scaling down.

### The Runner Part

Runner Specific or Highlighted Features:
- Start / Stop ASG schedule - specify a cron expression for when the cluster scales to 0 for Min and Desired (stop) and when it scales to 1 Min <yourvalue> Desired (start), after which autoscaling takes over.
- Runner information tagged in AWS and instance name and AWS account set as runner name for easy mapping of runners in GitLab to instances in AWS and vice versa.
- Runners self-tag as computetype-spot or computetype-ondemand to allow GitLab CI job level routing based on this information.
- Runners self-tag with gitlab runner executor type
- 

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
  * **Linux**: Generally assumes an AWS prepared AMI (all AWS utilities installed and configured for default operation). For Amazon Linux - assumes Amazon Linux **2**.
  * **Windows**: Generally assumes AWS prepared AMI (all AWS utilities installed and configured for default operation) using upgraded AWS EC2Launch client (and NOT older EC2Config) (For AWS prepared AMIs this equates to Server 2012 and later)

#### Linux
##### Userdata (includes download and execution of runner configuraiton script)
* **Resolved Script**: 
* **Userdata Execution Log**: cat /var/log/cloud-init-output.log
* **Rendered Custom Runner Configuration Script**: cat /custom_instance_configuration_script.sh
* **Termination Monitoring Script**: cat /etc/cron.d/MonitorTerminationHook.sh
* **Schedule of Termination Monitoring**: cat /etc/crontab

#### Windows
##### Userdata
* **Resolved Script**: cat C:\Windows\TEMP\UserScript.ps1
* **Userdata Execution Log**: cat C:\programdata\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log
* **Rendered Custom Runner Configuration Script**: cat $env:public\custom_instance_configuration_script.ps1
* **Termination Monitoring Script**: cat $env:public\MonitorTerminationHook.ps1
* **Schedule of Termination Monitoring**: schtasks /query /TN MonitorTerminationHook.ps1
### Scaling Troubleshooting and Testing

#### Windows
* Use this oneliner to install the console based text file editor 'nano' on headless windows: 
  
  `If (!(Test-Path env:chocolateyinstall)) {iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex} ; cinst -y nano`

#### CloudWatch Scaling
Alarms are not simple thresholds, they must be **breached* to enact the associated scaling rule.  For instance if your CPU utilization low threshold is 20% and your ASG starts and never goes above 20%, scale down will not occur because the alarm was not breached - the utilization simply never was above the threshold.

#### Ways To Test
* Generate Load
* Edit Scaling Alarms and Change Thresholds
#### CloudWatch Configuration and Operation (for memory and other stats)
##### Linux
* config: opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
* log file: tail /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log -f
* Running Status: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status
* Running Status: sudo systemctl status amazon-cloudwatch-agent