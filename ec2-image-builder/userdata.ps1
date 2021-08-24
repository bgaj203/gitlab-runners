
If (![bool](get-process amazon-ssm-agent -ErrorAction SilentlyContinue)) {
  logit "SSM Agent is not present - Installing SSM for Session Manager Access..."
  Invoke-WebRequest https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe -OutFile $env:PUBLIC\SSMAgent_latest.exe
  Start-Process	-wait -nonewwindow -FilePath $env:PUBLIC\SSMAgent_latest.exe -ArgumentList "/S"
}