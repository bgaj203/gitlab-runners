#IMPORTANT: AWS "Pseudo Parameters" cannot be used here because this script is retrieved after CloudFormation processes Pseudo Parameter Substitutions.
# this means any variable starting with "${AWS::", for example ${AWS::StackName}

#Note - gitlab-runner logs to the Application Eventlog as Provider / Source "gitlab-runner"

#This code is presumed to run in an ASG, which always spins new instances for updates to instances (newer ami, os patching, update runner version or tokens)
# This results in this code only ever running to install (during spin up) or uninstall (termination lifecycle hook)
# So it does not need to upgrade the runner binary in place or be able to unregister / re-register tokens.

$GITLABRunnerExecutor='shell'

$RunnerCompleteTagList = $RunnerOSTags, "glexecutor-$GITLABRunnerExecutor", $GITLABRunnerTagList -join ','

if (Test-Path variable:GITLABRunnerTagList) {$RunnerCompleteTagList = $RunnerCompleteTagList, "computetype-$($GITLABRunnerTagList.ToLower())" -join ','}
if (Test-Path variable:COMPUTETYPE) {$RunnerCompleteTagList = $RunnerCompleteTagList, "computetype-$($COMPUTETYPE.ToLower())" -join ','}

$MYIP="$(invoke-restmethod http://169.254.169.254/latest/meta-data/local-ipv4)"
$MYACCOUNTID="$((invoke-restmethod http://169.254.169.254/latest/dynamic/instance-identity/document).accountId)"
$RunnerName="$MYINSTANCEID-in-$MYACCOUNTID-in-$AWS_REGION"

Function logit ($Msg, $MsgType='Information', $ID='1') {
  If ($script:PSCommandPath -ne '' ) { $SourcePathName = $script:PSCommandPath ; $SourceName = split-path -leaf $SourcePathName } else { $SourceName = "Automation Code"; $SourcePathName = "Unknown" }
  Write-Host "[$(Get-date -format 'yyyy-MM-dd HH:mm:ss zzz')] $MsgType : From: $SourcePathName : $Msg"
  $applog = New-Object -TypeName System.Diagnostics.EventLog -argumentlist Application
  $applog.Source="$SourceName"
  $applog.WriteEntry("From: $SourcePathName : $Msg", $MsgType, $ID)
}

logit "Preflight checks for required endpoints..."
$UrlPortPairList="$GITLABRunnerInstanceURL=443 gitlab-runner-downloads.s3.amazonaws.com=443"
$FailureCount=0 ; $ConnectTimeoutMS = '3000'
foreach ($UrlPortPair in $UrlPortPairList.split(' '))
{
  $array=$UrlPortPair.split('='); $url=$array[0]; $port=$array[1]
  logit "TCP Test of $url on $port"
  $ErrorActionPreference = 'SilentlyContinue'
  $conntest = (new-object net.sockets.tcpclient).BeginConnect($url,$port,$null,$null)
  $conntestwait = $conntest.AsyncWaitHandle.WaitOne($ConnectTimeoutMS,$False)
  if (!$conntestwait)
  { logit "  Connection to $url on port $port failed"
    $conntest.close()
    $FailureCount++
  }
  else
  { logit "  Connection to $url on port $port succeeded" }
}
If ($FailureCount -gt 0)
{ logit "$failurecount tcp connect tests failed. Please check all networking configuration for problems."
  Exit $FailureCount
}

logit "Installing runner"

if (!(Test-Path $RunnerInstallRoot)) {New-Item -ItemType Directory -Path $RunnerInstallRoot}
#Most broadly compatible way to download file in PowerShell
If (!(Test-Path "$RunnerInstallRoot\gitlab-runner.exe")) {
  (New-Object System.Net.WebClient).DownloadFile("https://gitlab-runner-downloads.s3.amazonaws.com/$($GITLABRunnerVersion.tolower())/binaries/gitlab-runner-windows-amd64.exe", "$RunnerInstallRoot\gitlab-runner.exe")
}

#Write runner config.toml
set-content $env:public\config.toml -Value @"
concurrent = 4
log_level = "warning"
"@

pushd $RunnerInstallRoot
.\gitlab-runner.exe install

foreach ($RunnerRegToken in $GITLABRunnerRegTokenList.split(';')) {
 
  .\gitlab-runner.exe register `
  --config $RunnerConfigToml `
  --name $RunnerName `
  $OptionalParameters `
  --non-interactive `
  --url $GITLABRunnerInstanceURL `
  --registration-token $RunnerRegToken `
  --request-concurrency $GITLABRunnerConcurrentJobs `
  --tag-list $RunnerCompleteTagList `
  --executor $GITLABRunnerExecutor `
  --locked="false" `
  --maximum-timeout 10800 `
  --cache-type "s3" `
  --cache-path "/" `
  --cache-shared="true" `
  --cache-s3-server-address "s3.amazonaws.com" `
  --cache-s3-bucket-name $GITLABRunnerS3CacheBucket `
  --cache-s3-bucket-location $AWS_REGION
}

aws ec2 create-tags --region $AWS_REGION --resources $MYINSTANCEID --tags "Key=`"GitLabRunnerName`",Value=$RunnerName" "Key=`"GitLabURL`",Value=$GITLABRunnerInstanceURL" "Key=`"GitLabRunnerTags`",`"Value=$($RunnerCompleteTagList.split(',') -join ('\,'))`""

.\gitlab-runner.exe start

logit "Creating cleanup script for use with termination hook"

#Termination script hard codes variables to reduce api calls when it runs every minute
set-content $env:public\MonitorTerminationHook.ps1 -Value @"
Function logit (`$Msg, `$MsgType='Information', `$ID='1') {
  If (`$script:PSCommandPath -ne '' ) { `$SourcePathName = `$script:PSCommandPath ; `$SourceName = split-path -leaf `$SourcePathName } else { `$SourceName = "Automation Code"; `$SourcePathName = "Unknown" }
  Write-Host "[`$(Get-date -format 'yyyy-MM-dd HH:mm:ss zzz')] `$MsgType : From: `$SourcePathName : `$Msg"
  `$applog = New-Object -TypeName System.Diagnostics.EventLog -argumentlist Application
  `$applog.Source="`$SourceName"
  `$applog.WriteEntry("From: `$SourcePathName : `$Msg", `$MsgType, `$ID)
}

if ( (aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_REGION | convertfrom-json).AutoScalingInstances.LifecycleState -ilike "*Terminating*" ) {
  logit "This instance ($MYINSTANCEID) is being terminated, perform cleanup..."

  cd $RunnerInstallRoot

  if ( "$($COMPUTETYPE.ToLower())" -ne "spot" ) {
    logit "Instance is not spot compute, draining running jobs..."
    . $RunnerInstallRoot\gitlab-runner stop
  else
    logit "Instance is spot compute, deregistering runner immediately without draining running jobs..."
  }
  . $RunnerInstallRoot\gitlab-runner unregister --all-runners

  aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
  logit "This instance ($MYINSTANCEID) is ready for termination"
  logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
  }
"@
#unregister all runners
#stop service (wait for completion)

#cloudwatch metrics for Windows (https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-commandline-fleet.html)
# Get binary; Invoke-WebRequest -UseBasicParsing -Uri https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi -Outfile amazon-cloudwatch-agent.msi
# install it: msiexec /i amazon-cloudwatch-agent.msi /l*v $env:ProgramData\Amazon\amazon-cloudwatch-agent-install.log /qn
# configuration wizard: cd "C:\Program Files\Amazon\AmazonCloudWatchAgent" ; ./amazon-cloudwatch-agent-config-wizard.exe
# config agent config file location: $env:ProgramFiles\Amazon\AmazonCloudWatchAgent\config.json
# documentation advised location for custom config: $Env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json
# Start Agent: & "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c file:$env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json
# Logs: cat C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs\amazon-cloudwatch-agent.log, C:\ProgramData\Amazon\AmazonCloudWatchAgent\Logs\configuration-validation.log

popd

logit "Install CloudWatch Agent"
Invoke-WebRequest -UseBasicParsing -Uri https://s3.amazonaws.com/amazoncloudwatch-agent/windows/amd64/latest/amazon-cloudwatch-agent.msi -Outfile $env:public\amazon-cloudwatch-agent.msi
Start-Process msiexec.exe -Wait -ArgumentList "/i $env:public\amazon-cloudwatch-agent.msi /l*v $env:Public\amazon-cloudwatch-agent-install.log /qn ALLUSERS=1" -ErrorAction Stop -ErrorVariable MSIError

If (!(Test-Path $env:ProgramData\Amazon\AmazonCloudWatchAgent)) {New-Item $env:ProgramData\Amazon\AmazonCloudWatchAgent -ItemType Directory -Force}
logit "Writing CloudWatch Agent configuration"
set-content -Path "$env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json" -Value @'
{
  "metrics": {
    "aggregation_dimensions" : [["AutoScalingGroupName"], ["InstanceId"], ["InstanceType"], ["InstanceId","InstanceType"]],
    "append_dimensions": {
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}",
      "ImageId": "${aws:ImageId}",
      "InstanceId": "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}"
    },
    "metrics_collected": {
      "LogicalDisk": {
        "measurement": [
          "% Free Space"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "Memory": {
        "measurement": [
          "% Committed Bytes In Use"
        ],
        "metrics_collection_interval": 60
      },
      "Paging File": {
        "measurement": [
          "% Usage"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "PhysicalDisk": {
        "measurement": [
          "% Disk Time",
          "Disk Write Bytes/sec",
          "Disk Read Bytes/sec",
          "Disk Writes/sec",
          "Disk Reads/sec"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "*"
        ]
      },
      "Processor": {
        "measurement": [
          "% User Time",
          "% Idle Time",
          "% Interrupt Time"
        ],
        "metrics_collection_interval": 60,
        "resources": [
          "_Total"
        ]
      },
      "TCPv4": {
        "measurement": [
          "Connections Established"
        ],
        "metrics_collection_interval": 60
      },
      "TCPv6": {
        "measurement": [
          "Connections Established"
        ],
        "metrics_collection_interval": 60
      }
    }
  }
}
'@

logit "Checking if $env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json exists..."
If (Test-Path $env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json)
{
  logit "$env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json EXISTS! Displaying contents..."
  logit cat $env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json
}

logit "Starting CloudWatch Agent"
#& "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -a fetch-config -m ec2 -s -c file:$env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json
Start-Process powershell -wait -nologo -noninteractive -file "C:\Program Files\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent-ctl.ps1" -arguments "-a fetch-config -m ec2 -s -c file:$env:ProgramData\Amazon\AmazonCloudWatchAgent\amazon-cloudwatch-agent.json"

logit "Installing Git (via Chocolatey) for the shell runner..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12,[Net.SecurityProtocolType]::Tls11,[Net.SecurityProtocolType]::Tls; 
If (!(Test-Path env:chocolateyinstall)) {iwr https://chocolatey.org/install.ps1 -UseBasicParsing | iex} ; cinst -y git --no-progress

logit "Restarting the Runner to update with new system path that contains the git directory"
cd $RunnerInstallRoot
.\gitlab-runner.exe stop
.\gitlab-runner.exe start