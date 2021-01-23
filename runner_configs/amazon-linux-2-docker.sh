#!/usr/bin/env bash

# Update packages

#GITLABRunnerVersion="latest"
#RunnerOSTags="$($INSTANCEOSPLATFORM.ToLower())"
#GITLABRunnerTagList="TagA,TagB"
#RunnerConfigTomlTemplate #(Embedded, local or s3:// or http*://)
#GITLABRunnerRegTokenList='f3QN1vAeQq-MQx2_u9ML'
#GITLABRunnerInstanceURL='https://gitlab.demo.i2p.online/'
#RunnerInstallRoot='/gitlab-runner'
#RunnerConfigToml="$RunnerInstallRoot/config.toml"

MYIP="$(curl http://169.254.169.254/latest/meta-data/local-ipv4)"
MYACCOUNTID="$(curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep accountId| awk '{print $3}'|sed  's/"//g'|sed 's/,//g')"
RunnerName="$MYINSTANCEID-in-$MYACCOUNTID"

function logit() {
  LOGSTRING="$(date +"%_b %e %H:%M:%S") $(hostname) USERDATA_SCRIPT: $1"
  #For CloudFormation, if you already collect /var/log/cloud-init-output.log or /var/log/messsages (non amazon linux), then you could mute the next logging line
  echo "$LOGSTRING" >> /var/log/messages
}                     

#Detect package manager
if [[ -n "$(command -v yum)" ]] ; then
  PKGMGR='yum'
elif [[ -n "$(command -v apt-get)" ]] ; then
  PKGMGR='apt-get'
fi

set -ex
if [[ -n "$(command -v docker)" ]] ; then
  echo "Docker not present, installing..."
  amazon-linux-extras install docker
  usermod -a -G docker ec2-user
  systemctl enable docker.service
  systemctl start docker.service
fi

RunnerCompleteTagList="$RunnerOSTags,glexecutor-$GITLABRunnerExecutor,$GITLABRunnerTagList"

if [ -n ${COMPUTETYPE} ]; then RunnerCompleteTagList="$RunnerCompleteTagList, computetype-${COMPUTETYPE,,}"; fi

# Installing and configuring Gitlab Runner
if [ ! -d $RunnerInstallRoot ]; then mkdir -p $RunnerInstallRoot; fi

curl https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 --output $RunnerInstallRoot/gitlab-runner
chmod +x $RunnerInstallRoot/gitlab-runner
if ! id -u "gitlab-runner" >/dev/null 2>&1; then
  useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
  #sudo usermod -a -G docker gitlab-runner
fi
$RunnerInstallRoot/gitlab-runner install --user="gitlab-runner" --working-directory="/gitlab-runner"
echo -e "\nRunning scripts as '$(whoami)'\n\n"


# cat << EndOfRunnerConfigTOML > $RunnerConfigToml
# #Docker executor configuration
# concurrent = 4
# EndOfRunnerConfigTOML


$RunnerInstallRoot/gitlab-runner register \
  --non-interactive \
  --config $RunnerConfigToml \
  --url "$GITLABRunnerInstanceURL" \
  --registration-token "$GITLABRunnerRegTokenList" \
  --executor "$GITLABRunnerExecutor" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-image "docker:latest" \
  --docker-privileged \
  --run-untagged="true" \
  --tag-list "$RunnerCompleteTagList" \
  --locked 0 \
  --docker-tlsverify false \
  --docker-disable-cache false \
  --docker-shm-size 0 \
  --request-concurrency 4

$RunnerInstallRoot/gitlab-runner start

aws ec2 create-tags --region $AWS_REGION --resources $MYINSTANCEID --tags Key=GitLabRunnerName,Value="$RunnerName" Key=GitLabURL,Value="$GITLABRunnerInstanceURL" Key=GitLabRunnerTags,Value="$(echo $RunnerCompleteTagList | sed 's/,/\\\,/g')"

#$RunnerInstallRoot/gitlab-runner unregister --all-runners

#Escape all parens that are in quotes and all $ for variables that should wait until script runtime to be expanded. 
#Non-especaped $ will result in variable expansion DURING script writing which is used on purpose by this heredoc.
#This approach for termination hook is much simpler than those involving SNS or CloudWatch, but when deployed 
# on many instances it can result in a lot of ASG Describe API calls (which may be rate limited).

if [ ! -z "$NAMEOFASG" ] && [ "$ASGSelfMonitorTerminationInterval" != "Disabled" ] && [ "$WaitingForReboot" != "true" ]; then
  logit "Setting up termination monitoring because 5ASGSelfMonitorTerminationInterval is set to $ASGSelfMonitorTerminationInterval"
  SCRIPTNAME=/etc/cron.d/MonitorTerminationHook.sh
  SCRIPTFOLDER=$(dirname $SCRIPTNAME)
  SCRIPTBASENAME=$(basename $SCRIPTNAME)
  
  #Heredoc script
  cat << EndOfScript > $SCRIPTNAME
    function logit() {
      LOGSTRING="\$(date +'%_b %e %H:%M:%S') \$(hostname) TERMINATIONMON_SCRIPT: \$1"
      echo "\$LOGSTRING"
      echo "\$LOGSTRING" >> /var/log/messages
    }
    #These are resolved at script creation time to reduce api calls when this script runs every minute on instances.

    if [[ "\$(aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_REGION | jq --raw-output '.AutoScalingInstances[0] .LifecycleState')" == *"Terminating"* ]]; then
      logit "This instance ($MYINSTANCEID) is being terminated, perform cleanup..."

      $RunnerInstallRoot/gitlab-runner stop
      $RunnerInstallRoot/gitlab-runner unregister --all-runners

      #### PUT YOUR CLEANUP CODE HERE, DECIDE IF CLEANUP CODE SHOULD ERROR OUT OR SILENTLY FAIL (best effort cleanup)

      aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
      logit "This instance ($MYINSTANCEID) is ready for termination"
      logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
    fi
EndOfScript
fi

echo "Settings up CloudWatch Metrics to Enable Scaling on Memory Utilization"

cat << EndOfCWMetricsConfig > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "agent": {
    "metrics_collection_interval": 10,
    "logfile": "/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
  },
  "metrics": {
    "metrics_collected": {
      "mem": {
        "measurement": [
          "mem_used_percent",
          "mem_available_percent"
        ],
        "metrics_collection_interval": 1
      }
    },
    "append_dimensions": {
      "InstanceId": "$MYINSTANCEID",
      "InstanceType": "$(curl http://169.254.169.254/latest/meta-data/instance-type)",
      "AutoScalingGroupName": "$NAMEOFASG"
    },
    "aggregation_dimensions" : [["AutoScalingGroupName"]],
    "force_flush_interval" : 30
  }
}
EndOfCWMetricsConfig
yum install amazon-cloudwatch-agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent
#Check if running: sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status
#config: /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
#log file: tail /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log -f