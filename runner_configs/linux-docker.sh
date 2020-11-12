#from: https://medium.com/media/49867a766934c8ba3a1d419dd9acfd32#file-packer_provision-sh

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
$PKGMGR update && $PKGMGR install -y wget

# Installing and configuring Gitlab Runner
mkdir -p $RunnerInstallRoot
wget -O $RunnerInstallRoot/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
chmod +x $RunnerInstallRoot/gitlab-runner
useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
$RunnerInstallRoot/gitlab-runner install --user="gitlab-runner" --working-directory="/home/gitlab-runner"
echo -e "\nRunning scripts as '$(whoami)'\n\n"

$RunnerInstallRoot/gitlab-runner register                          \
  --non-interactive                                            \
  --url "$GITLABRunnerInstanceURL"                                \
  --registration-token "$GITLABRunnerRegTokenList"                     \
  --tag-list "docker"                                          \
  --request-concurrency 4                                      \
  --executor "$GITLABRunnerExecutor"                                          \
  --description "Some Runner Description"                      \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-image "docker:latest"                               \
  --docker-tlsverify false                                     \
  --docker-disable-cache false                                 \
  --docker-shm-size 0                                          \
  --locked="true"

$RunnerInstallRoot/gitlab-runner run            \
  --working-directory "$RunnerInstallRoot" \
  --config "/etc/gitlab-runner/config.toml" \
  --service "gitlab-runner"                 \
  --user "gitlab-runner"

#$RunnerInstallRoot/gitlab-runner unregister --all-runners


#This approach for termination hook is much simpler than those involving SNS or CloudWatch, but when deployed 
# on many instances it can result in a lot of ASG Describe API calls (which may be rate limited).
ASGSelfMonitorTerminationInterval=${5ASGSelfMonitorTerminationInterval}
if [ ! -z "$NAMEOFASG" ] && [ "$ASGSelfMonitorTerminationInterval" != "Disabled" ] && [ "$WaitingForReboot" != "true" ]; then
  logit "Setting up termination monitoring because 5ASGSelfMonitorTerminationInterval is set to $ASGSelfMonitorTerminationInterval"
  SCRIPTNAME=/etc/cron.d/MonitorTerminationHook.sh
  SCRIPTFOLDER=$(dirname $SCRIPTNAME)
  SCRIPTBASENAME=$(basename $SCRIPTNAME)
  
  #Heredoc script
  cat << EndOfScript > $SCRIPTNAME
    function logit() {
      LOGSTRING="\$(date +"%_b %e %H:%M:%S") \$(hostname) TERMINATIONMON_SCRIPT: \$1"
      echo "\$LOGSTRING"
      echo "\$LOGSTRING" >> /var/log/messages
    }
    #These are resolved at script creation time to reduce api calls when this script runs every minute on instances.

    if [[ "\$(aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_REGION | jq --raw-output '.AutoScalingInstances[0] .LifecycleState')" == *"Terminating"* ]]; then
      logit "This instance ($MYINSTANCEID) is being terminated, perform cleanup..."

      #### PUT YOUR CLEANUP CODE HERE, DECIDE IF CLEANUP CODE SHOULD ERROR OUT OR SILENTLY FAIL (best effort cleanup)

      aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
      logit "This instance ($MYINSTANCEID) is ready for termination"
      logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
    fi

EndOfScript