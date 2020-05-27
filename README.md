# GitLab Runner Autoscaling on AWS with Spot

The baseline for this template is the Ultimate AWS ASG Kickstart and Lab Kit with Spot Support.  It has many features and attibutes to learn about Autoscaling and spot and all of that is described here: https://gitlab.com/DarwinJS/ultimate-aws-asg-lab-kit/-/blob/master/README.md - It's worth it to read through the features.

### The Runner Part

At this time each runner is implemented as a bash or powershell script in the "runner_configs" directory.

These are then referenced in the primary Cloud Formation template as a full git raw URL in the CloudFormation parameter 3INSTConfigurationScript.

Currently the windows one is the most developed (because scaling shell runners is a need).

Note that these runner scripts have the following attributes (when fully completed):
* They are pulled dynamically by cloud formation - so they cannot use CloudFormation variable substitutions because that is done long before these are pulled and use.
* They must overwrite the TerminationMonitor script built into the CF template so that they can properly drain and unregister a runner on a scale-in operation.
* They rely on variable pass through from the main cloud formation code
* For runners with docker, the user should just provide an AWS prepared Amazon Linux 2 or Windows AMI with docker preinstalled in parameter
* They follow the best practice of using AWS ASG lifecycle hooks to give the instance time to be built - but more importantly, to allow it to drain and unregister on scale-in.

### Should I Bother for Scaling Runners (Docker-machine / AWS Fargate)

* Yes - because the dispatcher node should be in a single instance ASG for warm HA (respawn on death).  However, it would also benefit from all the other features of this template including repulling the latest AMI, latest patches and latest runner version upon a simple CF stack update.
* Docker-machine should be able to be completely replaced by a well tuned ASG housing the plain docker executor.