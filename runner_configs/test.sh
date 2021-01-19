
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo start amazon-ssm-agent
sudo curl -L https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 --output /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner
sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash
sudo /usr/local/bin/gitlab-runner install --user="gitlab-runner" --working-directory="/home/gitlab-runner"
sudo /usr/local/bin/gitlab-runner register --non-interactive --config /home/gitlab-runner/config.toml -url https://citi.gitlabms.com/ --registration-token KYpsqhgp-zwU_x14wLyV --executor docker --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" --docker-image "docker:latest"  --docker-privileged --name “New Runner From Scratch” --run-untagged="true" --locked 0
sudo /usr/local/bin/gitlab-runner start

sudo curl -L https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64 --output /usr/local/bin/gitlab-runner
sudo chmod +x /usr/local/bin/gitlab-runner

sudo useradd --comment 'GitLab Runner' --create-home gitlab-runner --shell /bin/bash

sudo /usr/local/bin/gitlab-runner install --user="gitlab-runner" --working-directory="/home/gitlab-runner"
sudo /usr/local/bin/gitlab-runner register --non-interactive --config /etc/gitlab-runner/config.toml --url https://gitlab-core.us.gitlabdemo.cloud/ --registration-token xTrR9x4xGeT5y13qyftN --executor docker --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" --docker-image "docker:latest"  --docker-privileged --run-untagged="true" --locked 0 --log-level info
sudo /usr/local/bin/gitlab-runner start 

#teardown
sudo /usr/local/bin/gitlab-runner stop
sudo /usr/local/bin/gitlab-runner unregister --all-runners
sudo /usr/local/bin/gitlab-runner uninstall
sudo rm /etc/gitlab-runner/config.toml


Gitlab runner user must be in same group as docker to run privileged?
Shell executor as root?
Shell executor - depends on user based shell config - no