
$AWSASGLabKitVersion="${1AAAAUltimateASGVersion}"
Function lc-success {aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-patching-reboot --auto-scaling-group-name $NAMEOFASG}
Function cf-success {cfn-signal --success true --stack ${AWS::StackName} --resource InstanceASG --region $AWS_REGION}
Trap { if ($8DBGTroubleShootingMode -eq 'true') { lc-success; cf-success}}
Function logit ($Msg, $MsgType='Information', $ID='1') {
  If ($script:PSCommandPath -ne '' ) { $SourcePathName = $script:PSCommandPath ; $SourceName = split-path -leaf $SourcePathName } else { $SourceName = "Automation Code"; $SourcePathName = "Unknown" }
  Write-Host "[$(Get-date -format 'yyyy-MM-dd HH:mm:ss zzz')] $MsgType : From: $SourcePathName : $Msg"
  $applog = New-Object -TypeName System.Diagnostics.EventLog -argumentlist Application
  $applog.Source="$SourceName"
  $applog.WriteEntry("From: $SourcePathName : $Msg", $MsgType, $ID)
}                
logit "Building Instance... with AWS ASG Lab Kit Version: $AWSASGLabKitVersion"
logit "Learn more at: $1AAAReadmeBlogPost"
logit "On 2012 R2 and earlier (Ec2Config) errors are logged to cat C:\Program Files\Amazon\Ec2ConfigService\Logs\Ec2ConfigLog.txt"
logit "On 2016 and later (Ec2Launch) errors are logged to cat C:\programdata\Amazon\EC2-Windows\Launch\Log\UserdataExecution.log" 
logit "Rendered script on an instance will be found at: C:\Windows\TEMP\UserScript.ps1"               

If ((![bool](get-process amazon-ssm-agent -ErrorAction SilentlyContinue)) -AND ($8DBGTroubleShootingMode -eq 'true')) {
  logit "8DBGTroubleShootingMode is true and SSM is not present - Installing SSM for Session Manager Access..."
  Invoke-WebRequest https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe -OutFile $env:USERPROFILE\SSMAgent_latest.exe
  Start-Process	-FilePath $env:USERPROFILE\SSMAgent_latest.exe -ArgumentList "/S"
}              
If (!(Test-Path "C:\Program Files\Amazon\AWSCLI\bin\aws.exe")) {
  logit "Installing AWS CLI to control lifecycle hook updates..."
  $AWSCLIURL="https://s3.amazonaws.com/aws-cli/AWSCLI64PY3.msi" #v1
  #$AWSCLIURL="https://awscli.amazonaws.com/AWSCLIV2.msi" #v2
  Invoke-WebRequest $AWSCLIURL -OutFile $env:USERPROFILE\AWSCLI.msi
  Start-Process	 -wait -nonewwindow -FilePath "msiexec.exe" -ArgumentList "/i $env:USERPROFILE\AWSCLI.msi /l*v $env:USERPROFILE\\AWSCLI-install.log /qn"
  $env:PATH="$env:PATH;C:\Program Files\Amazon\AWSCLI\bin"
  #$env:PATH="$env:PATH;C:\Program Files\Amazon\AWSCLIV2"
  If (![bool](get-command aws.exe)) {
    throw "AWS CLI did not install correctly"
  }
}
If (![bool](get-command cfn-signal.exe)) {
  logit "cfn-bootstrap is not present, installing it to control cloud formation completion..."
  Invoke-WebRequest https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-win64-latest.msi -OutFile $env:USERPROFILE\aws-cfn-bootstrap-win64-latest.msi
  Start-Process	 -wait -nonewwindow -FilePath "msiexec.exe" -ArgumentList "/i $env:USERPROFILE\aws-cfn-bootstrap-win64-latest.msi /l*v $env:USERPROFILE\aws-cfn-bootstrap-win64-latest.log /qn"
}
Function Test-PendingReboot
{
  Return ([bool]((get-itemproperty "hklm:SYSTEM\CurrentControlSet\Control\Session Manager").RebootPending) -OR 
  [bool]((get-itemproperty "HKLM:SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update").RebootRequired) -OR 
  [bool]((get-itemproperty "HKLM:SYSTEM\CurrentControlSet\Control\Session Manager").PendingFileRenameOperations) -OR 
  ((test-path c:\windows\winsxs\pending.xml) -AND ([bool](get-content c:\windows\winsxs\pending.xml | Select-String 'postAction="reboot"'))) -OR 
  ((get-itemproperty 'HKLM:SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\' | Select-Object -Expand 'ComputerName') -ine (get-itemproperty 'HKLM:SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\' | Select-Object -Expand 'ComputerName')) -OR 
  ((Test-Path "HKLM:SYSTEM\CurrentControlSet\Services\Netlogon\JoinDomain") -OR (Test-Path "HKLM:SYSTEM\CurrentControlSet\Services\Netlogon\AvoidSpnSet")))
}

$GITLABRunnerInstanceURL="${3GITLABRunnerInstanceURL}"
$GITLABRunnerRegTokenList="${3GITLABRunnerRegTokenList}"
$GITLABRunnerVersion="${3GITLABRunnerVersion}""
$GITLABRunnerTagList="${3GITLABRunnerTagList}"
$RunnerExecutor='shell'
$RunnerOSTags="$($INSTANCEOSPLATFORM.ToLower())"

$RunnerConfigTomlTemplate #(Embedded, local or s3:// or http*://)
#$GITLABRunnerRegTokenList='f3QN1vAeQq-MQx2_u9ML'

$RunnerInstallRoot='C:\GitLab-Runner'
$RunnerConfigToml="$RunnerInstallRoot\config.toml"
$INSTANCEOSPLATFORM="${1OSInstanceOSPlatform}"
$LAST_CF_PATCH_RUN="${1OSPatchRunDate}" #Forces change for patching rolling replacement and documents last CF triggered patching
$ACTUAL_PATCH_DATE="$(date -format 'yyyy-MM-dd')"
$MYINSTANCEID="$(invoke-restmethod http://169.254.169.254/latest/meta-data/instance-id)"
$AWS_REGION="$($(invoke-restmethod 169.254.169.254/latest/meta-data/placement/availability-zone) -replace '.$')"
$NAMEOFASG=$(aws ec2 describe-tags --region $AWS_REGION --filters Name=resource-id,Values=$MYINSTANCEID Name=key,Values=aws:autoscaling:groupName | convertfrom-json).tags.value
$NAMEOFSTACK="${AWS::StackName}"
$PATCHDONEFLAG="$env:USERPROFILE/patchingrebootwasdone.flg"
$1OSPatchScopeToUse="${1OSPatchScope}"
logit "Processing userdata script on instance: $MYINSTANCEID"
logit "Operating in Region: $AWS_REGION, launched from ASG: $NAMEOFASG"
$COMPUTETYPE="PROBLEM FINDING SPOT STATUS"
if ( "$((aws ec2 describe-instances --region $AWS_REGION --instance-id $MYINSTANCEID | convertfrom-json).Reservations.Instances.SpotInstanceRequestId)" -ne "" ) {
  $COMPUTETYPE='SPOT'
} else {
  $COMPUTETYPE='ONDEMAND'
}
aws ec2 create-tags --region $AWS_REGION --resources $MYINSTANCEID --tags "Key=`"COMPUTETYPE`",Value=$COMPUTETYPE"
if ($NAMEOFASG) {
  logit "Instance is in an ASG, will process lifecycle hooks"
  logit "Listing hook to verify permissions and hook presence"
  aws --region $AWS_REGION autoscaling describe-lifecycle-hooks --auto-scaling-group-name $NAMEOFASG
} else {
  logit "Instance is not in an ASG or if it is, the instance profile used does not have permissions to its own tags."
}

if (Test-Path $PATCHDONEFLAG) {
  logit "Completed a post-patching reboot, skipping patching check..."
} else {
  logit "Lets patch (including the kernel if necessary)..."
  logit "IMPORTANT: Windows update only updates installed os components.  If you install a component like IIS after this, you will need to run the patching commands again."

  if ((get-module -listavailable PSWindowsUpdate).count -lt 1) {
    Write-Host "PSWindowsUpdate is not available, installing..."
    install-module pswindowsupdate -SkipPublisherCheck -Force
  }

  Switch ($1OSPatchScopeToUse) {
    "SecurityOnly" { logit "Starting Patching."; Install-WindowsUpdate -MicrosoftUpdate -Category "Security Updates" -AcceptAll -Verbose; logit "Completed Patching." }
    "All" { logit "Starting Patching."; Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -Verbose; logit "Completed Patching." }
    "NoPatching-OnlyForDebugging" {logit -MsgType 'Warning' -ID 4 -Msg "No patching will be done - this setting is for debugging only (patch dates will still be set)" }
  }

  $LatestNGENBinary = $(Get-ChildItem $env:windir\microsoft.net\framework64\v*\ngen.exe | sort-object | select-object -last 1 | select-object -expand FullName)

  If ($LatestNGENBinary) {
    logit "Running Native Assembly Generation to process .NET updates immediately. Most errors can be ignored."
    Start-Process $LatestNGENBinary -ArgumentList 'update' -nonewwindow -wait
    logit "Native Assembly Generation Complete. Most errors can be ignored."
  } else {
    logit -MsgType 'Warning' -ID 7 "Warning ngen.exe was not found, which means .NET may not be installed - a highly unusual situation."
  }
  
  logit "ACTUAL_PATCH_DATE may be newer because this instance was autoscaled after the LAST_CF_PATCH_RUN"
  logit "LAST_CF_PATCH_RUN: $LAST_CF_PATCH_RUN"
  set-content $env:public/lastpatchingdata.ps1 "$LAST_CF_PATCH_RUN=$LAST_CF_PATCH_RUN"
  logit "ACTUAL_PATCH_DATE: $ACTUAL_PATCH_DATE"
  add-content $env:public/lastpatchingdata.ps1 "$ACTUAL_PATCH_DATE=$ACTUAL_PATCH_DATE"
}

if (("${3INSTInstallCodeDeploy}" -eq "true") -AND (![bool](get-service codedeployagent -ErrorAction SilentlyContinue))) {
  logit "Code deploy is requested, but not present, installing CodeDeploy"
  aws s3 cp s3://aws-codedeploy-$AWS_REGION/latest/codedeploy-agent.msi $env:USERPROFILE\codedeploy-agent.msi  --region $AWS_REGION
  Start-Process	 -wait -nonewwindow -FilePath "msiexec.exe" -ArgumentList "/i $env:USERPROFILE\codedeploy-agent.msi /l*v $env:USERPROFILE\codedeploy-agent.log /qn"
}

#This approach for termination hook is much simpler than those involving SNS or CloudWatch, but when deployed 
# on many instances it can result in a lot of ASG Describe API calls (which may be rate limited).
# variables identifying the instance and asg are hard coded into the script to reduce api calls.
$ASGSelfMonitorTerminationInterval=${5ASGSelfMonitorTerminationInterval}
if ($NAMEOFASG -AND ($ASGSelfMonitorTerminationInterval -ne "Disabled") -AND (!$WaitingForReboot -eq $True)) {
  logit "Setting up termination monitoring because 5ASGSelfMonitorTerminationInterval is set to $ASGSelfMonitorTerminationInterval"
  $SCRIPTNAME="$env:public\MonitorTerminationHook.ps1"
  
  #Heredoc script
  set-content $SCRIPTNAME -Value 
@"
    Function logit (`$Msg, `$MsgType='Information', `$ID='1') {
      If (`$script:PSCommandPath -ne '' ) { `$SourcePathName = `$script:PSCommandPath ; `$SourceName = split-path -leaf `$SourcePathName } else { `$SourceName = "Automation Code"; `$SourcePathName = "Unknown" }
      Write-Host "[`$(Get-date -format 'yyyy-MM-dd HH:mm:ss zzz')] `$MsgType : From: `$SourcePathName : `$Msg"
      `$applog = New-Object -TypeName System.Diagnostics.EventLog -argumentlist Application
      `$applog.Source="`$SourceName"
      `$applog.WriteEntry("From: `$SourcePathName : `$Msg", `$MsgType, `$ID)
    }

    if ( (aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_REGION | convertfrom-json).AutoScalingInstances.LifecycleState -ilike "*Terminating*" ) {
      logit "This instance ($MYINSTANCEID) is being terminated, perform cleanup..."

      #### PUT YOUR CLEANUP CODE HERE, DECIDE IF CLEANUP CODE SHOULD ERROR OUT OR SILENTLY FAIL (best effort cleanup)

      aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
      logit "This instance ($MYINSTANCEID) is ready for termination"
      logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
    }

"@

  logit "SCHEDULING: $SCRIPTNAME for every $ASGSelfMonitorTerminationInterval minutes to check for termination hook."
  schtasks.exe /create /sc MINUTE /MO $ASGSelfMonitorTerminationInterval /tn "MonitorTerminationHook.ps1" /ru SYSTEM /tr "powershell.exe -file $SCRIPTNAME"

}

$DefaultLocalCachedConfigScript="$env:public\custom_instance_configuration_script.ps1"
$INSTConfigurationScript="${3INSTConfigurationScript}"
logit "####"
logit "RUNNING CUSTOM INSTANCE CONFIGURATION CODE"

#If indicated as embedded, run it.
if ( $INSTConfigurationScript -eq "Embedded" ) {
  logit "CUSTOM CONFIG: Running embedded custom instance configuration script."
  ######
  # YOUR INSTANCE CONFIG CODE HERE

} elseif (($INSTConfigurationScript -ilike "http://*") -OR ($INSTConfigurationScript -ilike "https://*" )) {
  logit "CUSTOM CONFIG: Retrieving custom instance configuration script from $INSTConfigurationScript"
  if (!(Test-Path $DefaultLocalCachedConfigScript)) {
      logit "Pulling and executing from `"$INSTConfigurationScript`""
      [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"
      Invoke-RestMethod -OutFile $DefaultLocalCachedConfigScript -Uri $INSTConfigurationScript
    }
} elseif ( $INSTConfigurationScript -ilike "s3://*" ) {
  logit "CUSTOM CONFIG: Retrieving custom instance configuration script from $INSTConfigurationScript"
  if (!(Test-Path $DefaultLocalCachedConfigScript)) {
      aws s3 cp $INSTConfigurationScript $DefaultLocalCachedConfigScript
  } else {
    logit "$DefaultLocalCachedConfigScript was not found, will error out."
  }                  
} else {
  logit "CUSTOM CONFIG: Running custom instance configuration script in the local file named $INSTConfigurationScript"
  if (!(Test-Path $DefaultLocalCachedConfigScript)) {
    logit "Pointing \$DefaultLocalCachedConfigScript to $INSTConfigurationScript"
    DefaultLocalCachedConfigScript=$INSTConfigurationScript
  } else {
    logit "$DefaultLocalCachedConfigScript was not found, will error out."
  }
}

if ( $INSTConfigurationScript -ne "Embedded") {
  logit "Execution of the Non-Embedded Instance Configuration Script `"$DefaultLocalCachedConfigScript`" has been requested."
  if (Test-Path $DefaultLocalCachedConfigScript) {
    . "$DefaultLocalCachedConfigScript"
  } else {
    throw "ERROR: $DefaultLocalCachedConfigScript was not found, but is needed to complete instance setup."
    exit 9
  }
}
# END OF CUSTOM INSTANCE CONFIGURATION CODE"

If (Test-PendingReboot)
  {
    logit "Reboot pending, shutting down in 10 seconds (giving time for orchestrating automation to close out)..."
    $WaitingForReboot=$True
    logit "Ensuring userdata will be processed again"
    $path = 'C:\Program Files\Amazon\Ec2ConfigService\Settings\config.xml'
    if (Test-Path $path) {
      logit "Reseting Ec2Config userdata"
      $xml = [xml](Get-Content $path)
      $state = $xml.Ec2ConfigurationSettings.Plugins.Plugin | where {$_.Name -eq 'Ec2HandleUserData'}
      $state.State = 'Disabled'
      $xml.Save($path)
    }
    $path = 'C:\ProgramData\Amazon\Ec2-Windows\Launch\Config\LaunchConfig.json'
    if (Test-Path $path) {
      $ec2launchconfig = get-content $path | convertfrom-json
      if (!$($ec2launchconfig.handleUserData)) {
        logit "Reseting Ec2Launch userdata"
        $ec2launchconfig.handleUserData = $True
        $ec2launchconfig | convertto-json | set-content $path
      }
    }
    shutdown.exe /r /t 10
  } Else {
    Write-Host "A reboot is not pending, no action taken."
  }


if ($NAMEOFASG -AND !$WaitingForReboot) {
  logit "Completing lifecycle action hook so that ASG knows we are ready to be placed InService..."
  lc-success
}

if (!$WaitingForReboot) {
  logit "Cfn-signaling success..."
  cf-success
}

$DBGCPULoadPercentInitialValue=${8DBGCPULoadPercentInitialValue}
if (($WaitingForReboot -ne $True ) -AND ($DBGCPULoadPercentInitialValue)) {
  logit "Setting up CPU stressing because 8DBGCPULoadPercentInitialValue was set to $DBGCPULoadPercentInitialValue"
  Invoke-WebRequest https://github.com/vikyd/go-cpu-load/releases/download/0.0.1/go-cpu-load-win-amd64.exe -UseBasicParsing -outfile go-cpu-load-win-amd64.exe
  $CPUPercent="$(aws --region=$AWS_REGION ssm get-parameter --name $NAMEOFSTACK-SyntheticCPULoad --output text --query Parameter.Value)"
  while ( $CPUPercent -match "^[\d\.]+$" ) {
    logit "Stressing for 1 minutes at $CPUPercent percent CPU utilization."
    . .\go-cpu-load-win-amd64.exe -p $CPUPercent -t 60
    $CPUPercent="$(aws --region=$AWS_REGION ssm get-parameter --name $NAMEOFSTACK-SyntheticCPULoad --output text --query Parameter.Value)"
  }
  logit "Stopping CPU stressing due to receving non-numeric value: `"$CPUPercent`""
}
