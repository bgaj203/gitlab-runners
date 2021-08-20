
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

### First Time User Gotchas for Building Windows AMIs with EC2 Image Builder
- If you change the directory the "Working directory" because you don't like stuff in the root of C: (as we've all been taught about Windows best practices for quite some time), be sure to choose a directory that *already exists* - **it's extremely hard to find the root cause when you pick a non-existing directory - especially if you are new to automating Windows builds on AWS.**  You might want to use c:\users\public.  Note that the reversed slash on the default "C:/" does work because it is processed by PowerShell which can tolerate either slash for file system references. Note that there is no residue left on C:\ if you leave it at the default.
- Make sure to choose a large volume size.  AWS defaults to 30GB for Windows and Visual Studio takes way more than that. **This is another area where the root cause of your failure will be very challenging to find.** Probably 300 to 500 GB if you don't actually know what your CI build machine requires. Be sure to leave lots of working space.
- For some reason during my testing the direct build log links from EC2 Image Builder to CloudWatch logs were incorrect.  The logs are still there if you look manually, but the links go to a non-existent location.
