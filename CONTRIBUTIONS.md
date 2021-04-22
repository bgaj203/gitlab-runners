
# Branch Testing Before Merging to Main

## Setting up a new development branch
1. Name the branch exactly as the new version (e.g. v1.4.5-alpha10)
2. Search and replace all occurances of the old branch to the new (e.g. v1.4.2-alpha9 == replace with ==> v1.4.5-alpha10)
3. Files under "runner_configs" use raw file retrieval from gitlab to pull these files, if they might change on this branch, the retrieval must be updated to isolate to the branch by replacing occurances of `/-/raw/main/` with `/-/raw/v1.4.5-alpha10/`
4. In the public S3 bucket that houses the templates, create a new version key (subdirectory) with the same name (e.g. v1.4.5-alpha10)


## Right before merge to main
1. Reverse the raw retreieval back main (do this every time to be sure) by replacing occurances of `/-/raw/v1.4.5-alpha10/` with `/-/raw/main/` (for example version v1.4.5-alpha10)

> Note: The pointers in to the CloudFormation key with the version number can be left intact to allow folks to peg to a version when necessary.