#IMPORTANT: AWS "Pseudo Parameters" cannot be used here because this script is retrieved after CloudFormation processes Pseudo Parameter Substitutions.
# this means any variable starting with "${AWS::", for example ${AWS::StackName}

#Note - gitlab-runner logs to the Application Eventlog as Provider / Source "gitlab-runner"

#This code is presumed to run in an ASG, which always spins new instances for updates to instances (newer ami, os patching, update runner version or tokens)
# This results in this code only ever running to install (during spin up) or uninstall (termination lifecycle hook)
# So it does not need to upgrade the runner binary in place or be able to unregister / re-register tokens.

#Runner Token List
#$INSTANCEOSPLATFORM="Windows"
#$AWS_DEFAULT_REGION="$($(invoke-restmethod 169.254.169.254/latest/meta-data/placement/availability-zone) -replace '.$')"
#$NAMEOFASG=$(aws ec2 describe-tags --region $AWS_DEFAULT_REGION --filters Name=resource-id,Values=$MYINSTANCEID Name=key,Values=aws:autoscaling:groupName | convertfrom-json).tags.value
#$MYINSTANCEID="$(invoke-restmethod http://169.254.169.254/latest/meta-data/instance-id)"
$RunnerVersion="latest"
$RunnerExecutor='shell'
$RunnerOSTags="$($INSTANCEOSPLATFORM.ToLower())"
$RunnerTagList="TagA,TagB"
$RunnerConfigTomlTemplate #(Embedded, local or s3:// or http*://)
#$GITLABRunnerRegTokenList='f3QN1vAeQq-MQx2_u9ML'
$RunnerGitLabInstanceURL='https://gitlab.demo.i2p.online/'

$RunnerCompleteTagList = $RunnerOSTags, $RunnerExecutor, $RunnerTagList -join ','

$RunnerInstallRoot='C:\GitLab-Runner'

write-host "GITLABRunnerRegTokenList: $GITLABRunnerRegTokenList"

$MYIP="$(invoke-restmethod http://169.254.169.254/latest/meta-data/local-ipv4)"
$MYACCOUNTID="$((invoke-restmethod http://169.254.169.254/latest/dynamic/instance-identity/document).accountId)"
$RunnerName="$MYINSTANCEID-in-$MYACCOUNTID"

Function logit ($Msg, $MsgType='Information', $ID='1') {
  If ($script:PSCommandPath -ne '' ) { $SourcePathName = $script:PSCommandPath ; $SourceName = split-path -leaf $SourcePathName } else { $SourceName = "Automation Code"; $SourcePathName = "Unknown" }
  Write-Host "[$(Get-date -format 'yyyy-MM-dd HH:mm:ss zzz')] $MsgType : From: $SourcePathName : $Msg"
  $applog = New-Object -TypeName System.Diagnostics.EventLog -argumentlist Application
  $applog.Source="$SourceName"
  $applog.WriteEntry("From: $SourcePathName : $Msg", $MsgType, $ID)
}

logit "Installing runner"

if (!(Test-Path $RunnerInstallRoot)) {New-Item -ItemType Directory -Path $RunnerInstallRoot}
#Most broadly compatible way to download file in PowerShell
If (!(Test-Path "$RunnerInstallRoot\gitlab-runner.exe")) {
  (New-Object System.Net.WebClient).DownloadFile("https://gitlab-runner-downloads.s3.amazonaws.com/$($RunnerVersion.tolower())/binaries/gitlab-runner-windows-amd64.exe", "$RunnerInstallRoot\gitlab-runner.exe")
}

#If runnerconfig template is provided, download if remote, validate local file exists

if ($RunnerConfigTomlTemplate) {
  $OptionalParameters = " --template-config $RunnerConfigTomlTemplate "
}

cd $RunnerInstallRoot
.\gitlab-runner.exe install

foreach ($RunnerRegToken in $GITLABRunnerRegTokenList.split(',')) {
 
  .\gitlab-runner.exe register `
     --config $RunnerInstallRoot\config.toml `
     $OptionalParameters `
     --non-interactive `
     --url $RunnerGitLabInstanceURL `
     --registration-token $RunnerRegToken `
     --name $RunnerName `
     --tag-list $RunnerCompleteTagList `
     --executor $RunnerExecutor
}

#rename instance to include -glrunner ?
#aws ec2 describe-tags --filters "Name=resource-id,Values=$MYINSTANCEID"

aws ec2 create-tags --region $AWS_DEFAULT_REGION --resources $MYINSTANCEID --tags "Key=`"GitLabRunnerName`",Value=$RunnerName" "Key=`"GitLabURL`",Value=$RunnerGitLabInstanceURL" "Key=`"GitLabRunnerTags`",`"Value=$($RunnerCompleteTagList.split(',') -join ('\,'))`""

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

if ( (aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_DEFAULT_REGION | convertfrom-json).AutoScalingInstances.LifecycleState -ilike "*Terminating*" ) {
  logit "This instance ($MYINSTANCEID) is being terminated, perform cleanup..."

  cd $RunnerInstallRoot
  .\gitlab-runner.exe unregister --config $RunnerInstallRoot\config.toml --all-runners 

  .\gitlab-runner.exe stop

  aws autoscaling complete-lifecycle-action --region $AWS_DEFAULT_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
  logit "This instance ($MYINSTANCEID) is ready for termination"
  logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
  }
"@
#unregister all runners
#stop service (wait for completion)