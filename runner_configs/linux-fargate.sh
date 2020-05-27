#from: https://medium.com/media/49867a766934c8ba3a1d419dd9acfd32#file-packer_provision-sh

#!/usr/bin/env bash

# Update packages

#Detect package manager
if [[ -n "$(command -v yum)" ]] ; then
  PKGMGR='yum'
elif [[ -n "$(command -v apt-get)" ]] ; then
  PKGMGR='apt-get'
fi

set -ex
$PKGMGR update && $PKGMGR install -y wget

# Installing and configuring Gitlab Runner
#wget -O /usr/local/bin/gitlab-runner https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
#chmod +x /usr/local/bin/gitlab-runner
#useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
#/usr/local/bin/gitlab-runner install --user="gitlab-runner" --working-directory="/home/gitlab-runner"
#echo -e "\nRunning scripts as '$(whoami)'\n\n"
sudo mkdir -p /opt/gitlab-runner/{metadata,builds,cache}
curl -s https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | sudo bash
sudo apt install gitlab-runner

cat << EOF > /etc/gitlab-runner/config.toml
[[runners]]
  builds_dir = "/opt/gitlab-runner/builds"
  cache_dir = "/opt/gitlab-runner/cache"
  [runners.custom]
    config_exec = "/opt/gitlab-runner/fargate"
    config_args = ["--config", "/etc/gitlab-runner/fargate.toml", "custom", "config"]
    prepare_exec = "/opt/gitlab-runner/fargate"
    prepare_args = ["--config", "/etc/gitlab-runner/fargate.toml", "custom", "prepare"]
    run_exec = "/opt/gitlab-runner/fargate"
    run_args = ["--config", "/etc/gitlab-runner/fargate.toml", "custom", "run"]
    cleanup_exec = "/opt/gitlab-runner/fargate"
    cleanup_args = ["--config", "/etc/gitlab-runner/fargate.toml", "custom", "cleanup"]
EOF

cat << EOF > /etc/gitlab-runner/fargate.toml  
LogLevel = "info"
LogFormat = "text"

[Fargate]
  Cluster = "test-cluster"
  Region = "us-east-2"
  Subnet = "subnet-xxxxxx"
  SecurityGroup = "sg-xxxxxxxxxxxxx"
  TaskDefinition = "test-task:1"
  EnablePublicIP = true

[TaskMetadata]
  Directory = "/opt/gitlab-runner/metadata"

[SSH]
  Username = "root"
  PrivateKeyPath = "/root/.ssh/id_rsa"
EOF


/usr/local/bin/gitlab-runner register                          \
  --non-interactive                                            \
  --url "https://<GITLAB_URL>/"                                \
  --registration-token "<GITLAB_REG_TOKEN"                     \
  --tag-list "docker"                                          \
  --request-concurrency 4                                      \
  --executor "docker"                                          \
  --description "Some Runner Description"                      \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-image "docker:latest"                               \
  --docker-tlsverify false                                     \
  --docker-disable-cache false                                 \
  --docker-shm-size 0                                          \
  --locked="true"


