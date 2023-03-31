
#Commands to run this:
# wget https://gitlab.com/guided-explorations/aws/gitlab-runner-autoscaling-aws-asg/-/raw/yocto/runner_configs/yocto-linux-docker-non-asg.sh
# chmod +x yocto-linux-docker-non-asg.sh
# ./yocto-linux-docker-non-asg.sh -r <your runner registration token> -g <gitlab url> - optional, defaults to https://gitlab.com

# ******************
# Begin Yocto specific

while :; do
    case $1 in
        -h|-\?|--help)
            echo "$0 -r [runner registration token]"
            exit
            ;;
        -g|--gitlab-url)
            if [ "$2" ]; then
                PassedGLURL=$2
                shift
            fi
            ;;
        -r|--registration-token)
            if [ "$2" ]; then
                PassedRegTokenList=$2
                shift
            else
                die 'ERROR: "-r|--registration-token" requires a non-empty option argument.'
            fi
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac

    shift
done

if [[ -z "$PassedRegTokenList" ]];then 
  echo "ERROR: Must provide a runner registration token with -r|--registration-token"
  exit 5 
else 
  GITLABRunnerRegTokenList=$PassedRegTokenList
fi

wget https://github.com/moparisthebest/static-curl/releases/download/v8.0.1/curl-aarch64 -O /bin/curl
chmod +x /bin/curl

GITLABRunnerInstanceURL="https://gitlab.com" #default
if [[ -n "$PassedGLURL" ]]; then GITLABRunnerInstanceURL=$PassedGLURL; fi

GITLABRunnerExecutor="docker"
RunnerName="Yocto-Runner"
GITLABRunnerConcurrentJobs=1
RunnerOSTags="yocto-linux"
RunnerInstallRoot=/gitlab-runner
COMPUTETYPE=ondemand
RunnerConfigToml="/etc/gitlab-runner/config.toml"
OSInstanceLinuxArch="arm64"
GITLABRunnerVersion="v15.10.1"
DefaultRunnerImage="docker:latest"

# End Yocto specific
# ******************

IMDS_TOKEN="$(curl -X PUT http://169.254.169.254/latest/api/token -H X-aws-ec2-metadata-token-ttl-seconds:21600)"
MYIP="$(curl -H X-aws-ec2-metadata-token:$IMDS_TOKEN http://169.254.169.254/latest/meta-data/local-ipv4)"
MYACCOUNTID="$(curl -H X-aws-ec2-metadata-token:$IMDS_TOKEN http://169.254.169.254/latest/dynamic/instance-identity/document | grep accountId | awk '{print $3}' | sed  's/"//g' | sed 's/,//g')"

AWS_REGION="$(curl -s -H X-aws-ec2-metadata-token:$IMDS_TOKEN 169.254.169.254/latest/meta-data/placement/availability-zone | sed 's/.$//')"
MYINSTANCEID="$(curl -H X-aws-ec2-metadata-token:$IMDS_TOKEN http://169.254.169.254/latest/meta-data/instance-id)"

RunnerName="$MYINSTANCEID-in-$MYACCOUNTID-at-$AWS_REGION"

function logit() {
  LOGSTRING="$(date +"%_b %e %H:%M:%S") $(hostname) Runner Registration Script: $1"
  #For CloudFormation, if you already collect /var/log/cloud-init-output.log or /var/log/messsages (non amazon linux), then you could mute the next logging line
  echo "$LOGSTRING" >> /var/log/messages
}

logit "Preflight checks for required endpoints..."
urlportpairlist="$(echo $GITLABRunnerInstanceURL | cut -d'/' -f3 | cut -d':' -f1)=443 gitlab-runner-downloads.s3.amazonaws.com=443"
failurecount=0
for urlportpair in $urlportpairlist; do
  set -- $(echo $urlportpair | tr '=' ' ') ; url=$1 ; port=$2
  logit "TCP Test of $url on $port"
  cat < /dev/null > /dev/tcp/$url/$port
  if [ "$?" -ne 0 ]; then
    logit "  Connection to $url on port $port failed"
    ((failurecount++))
  else
    logit "  Connection to $url on port $port succeeded"
  fi
done

#if [ $failurecount -gt 0 ]; then
# logit "$failurecount tcp connect tests failed. Please check all networking configuration for problems."
#  if [ -f /opt/aws/bin/cfn-signal ]; then
#    /opt/aws/bin/cfn-signal --success false --stack ${AWS::StackName} --resource InstanceASG --region $AWS_REGION --reason "Cant connect to GitLab or other endpoints"
#  fi
#  exit $failurecount
#fi

RunnerCompleteTagList="$RunnerOSTags,glexecutor-$GITLABRunnerExecutor,${OSInstanceLinuxArch,,}"

if [[ -n "${GITLABRunnerTagList}" ]]; then RunnerCompleteTagList="$RunnerCompleteTagList,${GITLABRunnerTagList,,}"; fi
if [[ -n "${COMPUTETYPE}" ]]; then RunnerCompleteTagList="$RunnerCompleteTagList,computetype-${COMPUTETYPE,,}"; fi

# Installing and configuring Gitlab Runner
if [ ! -d $RunnerInstallRoot ]; then mkdir -p $RunnerInstallRoot; fi

curl https://gitlab-runner-downloads.s3.amazonaws.com/${GITLABRunnerVersion,,}/binaries/gitlab-runner-linux-${OSInstanceLinuxArch} --output $RunnerInstallRoot/gitlab-runner
chmod +x $RunnerInstallRoot/gitlab-runner
if ! id -u "gitlab-runner" >/dev/null 2>&1; then
  useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
fi
$RunnerInstallRoot/gitlab-runner install --user="gitlab-runner" --working-directory="/gitlab-runner"
echo -e "\nRunning scripts as '$(whoami)'\n\n"

for RunnerRegToken in ${GITLABRunnerRegTokenList//;/ }
do
  echo "Running   $RunnerInstallRoot/gitlab-runner --log-level="info" register \
    --non-interactive \
    --name $RunnerName \
    --config $RunnerConfigToml \
    --url "$GITLABRunnerInstanceURL" \
    --registration-token "$RunnerRegToken" \
    --executor "$GITLABRunnerExecutor" \
    --run-untagged="true" \
    --tag-list "$RunnerCompleteTagList" \
    --locked="false" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
    --docker-image $DefaultRunnerImage \
    --docker-privileged \
    --docker-tlsverify="false" \
    --docker-disable-cache="false" \
    --docker-shm-size 0 "

  $RunnerInstallRoot/gitlab-runner --log-level="info" register \
    --non-interactive \
    --name $RunnerName \
    --config $RunnerConfigToml \
    --url "$GITLABRunnerInstanceURL" \
    --registration-token "$RunnerRegToken" \
    --executor "$GITLABRunnerExecutor" \
    --run-untagged="true" \
    --tag-list "$RunnerCompleteTagList" \
    --locked="false" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
    --docker-image $DefaultRunnerImage \
    --docker-privileged \
    --docker-tlsverify="false" \
    --docker-disable-cache="false" \
    --docker-shm-size 0 
    #--cache-type "s3" \
    #--cache-path "/" \
    #--cache-shared="true" \
    #--cache-s3-server-address "s3.amazonaws.com" \
    #--cache-s3-bucket-name $GITLABRunnerS3CacheBucket \
    #--cache-s3-bucket-location $AWS_REGION \
done

sed -i "s/^\s*concurrent.*/concurrent = $GITLABRunnerConcurrentJobs/g" $RunnerConfigToml

$RunnerInstallRoot/gitlab-runner start