
EC2 Image Builder is very convenient way to build and distribute and share golden AMI images.

### Advantages
- It is much less work that getting packer running (which this author has done on and off Amazon)
- It does not open up WinRM which is frequently left in a wide-open state just because it was used to provision a golden image. Read more about the problem and a chocolatey package that solves it [WinRM For Provisioning - Close The Door On The Way Out Eh!](https://missionimpossiblecode.io/post/winrm-for-provisioning-close-the-door-on-the-way-out-eh/) and 
- it has automation for deploying the AMI to regions and permissioning it to accounts.
- it supports revisions of all it's objects
- it supports scheduled runs
- it supports AWS License Manager
- it logs builds to CloudWatch

It is a meta-PaaS in that it is a service that completely simplifies building pipelines for building OS images - which usually have many unique challenges compared to standard software building pipelines.