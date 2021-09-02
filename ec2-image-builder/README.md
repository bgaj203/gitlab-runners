
EC2 Image Builder is very convenient way to build and distribute and share golden AMI images.

### Advantages
- It is much less work that getting packer running (which this author has done on and off Amazon)
- It does not open up WinRM which is frequently left in a wide-open state just because it was used to provision a golden image. Read more about the problem and a chocolatey package that solves it [WinRM For Provisioning - Close The Door On The Way Out Eh!](https://missionimpossiblecode.io/post/winrm-for-provisioning-close-the-door-on-the-way-out-eh/) and 
- it has automation for deploying the AMI to regions and permissioning it to accounts.
- it supports revisions of all it's objects
- it supports scheduled runs
- it supports AWS License Manager
- it logs builds to CloudWatch
- AWS provides STIG build components for preparing GovCloud images

It is a meta-PaaS in that it is a service that completely simplifies building pipelines for building OS images - which usually have many unique challenges compared to standard software building pipelines.

### First Time User Gotchas for Building Windows AMIs with EC2 Image Builder
- It seems like AWS EC2 Image Builder does not continue after running the included component ec2-image-builder/windows-same-as-gitlab-com.yml on the AWS Windows 2019 Full AMI, yet the exact same component works fine with AWS Windows **2016** Full AMI.
- If you change the directory the "Working directory" because you don't like stuff in the root of C: (as we've all been taught about Windows best practices for quite some time), be sure to choose a directory that *already exists* - **it's extremely hard to find the root cause when you pick a non-existing directory - especially if you are new to automating Windows builds on AWS.**  You might want to use c:\users\public.  Note that the reversed slash on the default "C:/" does work because it is processed by PowerShell which can tolerate either slash for file system references. Note that there is no residue left on C:\ if you leave it at the default.
- Make sure to choose a large volume size.  AWS defaults to 30GB for Windows and Visual Studio takes way more than that. **This is another area where the root cause of your failure will be very challenging to find.** Probably 300 to 500 GB if you don't actually know what your CI build machine requires. Be sure to leave lots of working space.
- For some reason during my testing the direct build log links from EC2 Image Builder to CloudWatch logs were incorrect.  The logs are still there if you look manually, but the links go to a non-existent location.
- If you are building additional components, the AWS component validator does not like certain syntax at the start of a line that is valid powershell.  For instance `@("item1","item2") | foreach {write-host "Item is $psitem"}`.  If you run into this there is usally a way to recraft your PowerShell to make it happy.  In this case `write-host ("item1","item2") | foreach {write-host "Item is $psitem"}` works fine.
- The web editors for your components in the AWS EC2 Image Builder console allow smart quotes.  These are death for PowerShell.  Thankfully you can visually distinguish them in the editor and if you watch carefully the syntax editor will not highlight the quoted content when a smart quote is used - a cue that you may have a smart quote.  
- I have found cases where powershell that I test prospective powershell code in an AMI built by EC2 Image Builder and that code does not work during an EC2 Image Builder build.  For instance, this `` had to be updated to this `copy-item "C:\Users\Public\MSBuild.Microsoft.VisualStudio.Web.targets.11.0.2.1\tools\VSToolsPath\*" “C:\Program Files (x86)\MSBuild\Microsoft\VisualStudio\v11.0” -recurse` to avoid the build choking on `(x86)` as being a command. I've always scratched my head at the parens in that directory name and it's variable reference - but this could happen in other areas as well.  Use single quotes when you can to avoid undesirable attempted expansions.
- The AWS component for PowerShell Core is using version 6.x, this automation uses chocolatey to install the latest (7.1.x as of this writing)
- The AWS shutdown process clears out non-default folders from c:\ - so installing software here is not adviseable.
- Seperate "Test" Components are important in Windows for at least these reasons:
  1. Sysprep is run by EC2 Image Builder (after "validate" steps of an install component) and there is a small possibility it may affect the operation of some software.
  2. AWS cleans out any folders at the root of c:\ - a test stage will catch the mistake of installing something there.
  3. Many software installations that update the system path do not work correctly until after a reboot - the Test components run on a fresh boot off of the Image Builder created AMI - so doing the tests at this time allows proper validation of any configuration requiring a reboot to valudate correctly.

### Bigger Gotcha: Hanging Sysprep
AWS does not provide a reboot component during BUILD, yet SYSPREP will hang if the system is "reboot pending DUE TO windows updates".  With complex CI build agent dependencies like those in [ec2-image-builder/windows-same-as-gitlab-com.yml](ec2-image-builder/windows-same-as-gitlab-com.yml), the situation of having run Windows updates that cause a pending reboot will be frequent.

To diagnose this situation (or other sysprep hangs), 
1. SSM into the machine being built (it will be hanging in "Building" mode for way longer than expected)
2. Do `get-process sysprep` to see if sysprep is still running
3. If yes, review the contents of  C:\Windows\system32\sysprep\panther\setupact.log

The root cause error for the common condition of a windows update pending reboot says "Sysprep_Clean_Validate_0pk:There are one or more Windows updates that require a reboot. To run Sysprep, reboot the computer and restart the application.[gle=0x000036b7]

**NOTE:** Sysprep has this odd non-exiting error hang for other reasons as well - so this troubleshooting information may apply to other situations.

### GitLab Runner Requirements
- The EC2 Image Builder recipe must include the AWS prepared "Chocolatey" component and it must be sequenced before the component in this documentation.
- GitLab Runner assumes PowerShell Core (pwsh.exe) is on the path for Windows machines - so the AWS prepared "PowerShell Core" component must be installed (order is not important) for GitLab runner to run PowerShell scripts in gitlab-ci.yml. If you need Windows PowerShell you can call it from an initial PowerShell Core script.
- Visual studio build tools require a volume much larger than the AWS Windows default of 30GB - but it is hard to diagnose when you run out spaces during EC2 Image Builder builds - so pick a value larger that Visual Studio and with plenty of scratch space - 500-750GB should do it - you might be able to tune that value to be lower depending on your build.

### EC2 Image Builder Files
- **windows-netframework4-component.yml** - builds a runner specifically for being able to build a .NET 4.5 version of nopcommerce.
- **windows-same-as-gitlab-com.yml** - mimics the Windows runner configuration used on GitLab.com. [Configuration information is here.](https://gitlab.com/gitlab-org/ci-cd/shared-runners/images/gcp/windows-containers/-/blob/main/cookbooks/preinstalled-software/README.md)
- **windows-reboot-at-end-if-needed.yml** - experimental -  This component can detect if, at the end 
- **userdata.ps1** - the userdata snippet required in an EC2 Image Builder Recipe so that EC2 Image Builder can run commands to install software.
