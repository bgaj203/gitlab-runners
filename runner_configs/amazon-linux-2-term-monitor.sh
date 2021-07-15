
function logit() {
  LOGSTRING="$(date +'%_b %e %H:%M:%S') $(hostname) TERMINATIONMON_SCRIPT: $1"
  echo "$LOGSTRING"
  echo "$LOGSTRING" >> /var/log/messages
}
#These are resolved at script creation time to reduce api calls when this script runs every minute on instances.

#Termination types: 
#  1) Non-spot - happens to non-spot instances and spot instances when termination is due to scale-in or other non-spot termination event. No limit on wrapup / cleanup time.
#  2) spot termination only happens to spot instances and only if initiated by a spot event. Limited to 2 minutes from notification time until hard termination.

#Check for non-spot termination (happens to spot instances too)
if [[ "$(aws autoscaling describe-auto-scaling-instances --instance-ids $MYINSTANCEID --region $AWS_REGION | jq --raw-output '.AutoScalingInstances[0] .LifecycleState')" == *"Terminating"* ]]; then
  logit "This instance ($MYINSTANCEID) is experiencing a non-spot termination, perform cleanup..."
  logit "Draining jobs (best effort)..."
  $RunnerInstallRoot/gitlab-runner stop
  Terminating='true'
elif [ "${COMPUTETYPE,,}" == "spot" ]; then
  #if we aren't doing a regular termination and we're spot, use the cycle to check for spot termination multiple times per minute.
  let totaliterations=ASGSelfMonitorTerminationInterval*SpotTermChecksPerMin
  until [[ $LoopIteration -eq $totaliterations || "${Terminating}" == "true" ]]; do
    if [[ $(curl -s -o /dev/null -w '%{http_code}\n' -v ${MetaDataURL}/latest/meta-data/spot/instance-action) != 404 ]]; then
      logit "Instance is spot compute, deregistering runner immediately without draining running jobs..."
      Terminating='true'
    fi
    sleep $(awk "BEGIN {printf \"%.2f\",1/$SpotTermChecksPerMin}")
    ((LoopIteration=LoopIteration+1))
  done
fi

if [[ "${Terminating}" == "true" ]]; then
  #Common termination items
  logit "Deregistering GitLab Runners..."
  $RunnerInstallRoot/gitlab-runner unregister --all-runners

  aws autoscaling complete-lifecycle-action --region $AWS_REGION --lifecycle-action-result CONTINUE --instance-id $MYINSTANCEID --lifecycle-hook-name instance-terminating --auto-scaling-group-name $NAMEOFASG
  logit "This instance ($MYINSTANCEID) is ready for termination"
  logit "Lifecycle CONTINUE was sent to termination hook in ASG: $NAMEOFASG for this instance ($MYINSTANCEID)."
fi