
# Branch Testing Before Merging to Main

## Community Contributions

For your initial submission, please:

1. Fork this repository to a *public* location (so that your contributions can be editted)
2. Create a new branch FROM THE develop branch (this is even more important if there is a release candidate underway as there are many paths in the project that are updated to point to the new version)
3. Create your changes
4. **Test** your changes from the code you have merged (please do not test outside of the branch submissions and only splice over your working code - because this process frequently results in non-working code)
5. Create a Merge Request (MR) back to the the `develop` branch of this repository (the MR interface likely defaults to `main` branch).
6. In the MR template, be sure to specify how you tested, that you tested the exact branch code and that the test results were successful.
7. In the MR, ensure that `Allow commits from members who can merge to the target branch.` is checked like this screenshot. (Your repository must be public)

    ![Screen_Shot_2021-11-16_at_8.58.14_AM](/uploads/bcddc8865c83be2de14c08934394791c/Screen_Shot_2021-11-16_at_8.58.14_AM.png)

## Prerelease Procedures

- a prerelease version tag will be added in the develop branch.
- each issue needs a seperate MR and dedicated branch and be merged into develop (so that changes are easy to track, test and back out)
- periodically the prerelease tag will be moved to the latest commits when testing is desired.

## Release Procedures

1. The version string embedded throughout the code will stay as is to enable version safety
2. `develop` will be merged into `main`
3. the templates will be pushed to the existing s3 key that contains the versoin string
4. the Git version tag will be pointed at the tip of the `main` branch
5. A GitLab Release will be created from the Git tag.

The above results in the default view of the README.md and easybuttons.md pointing to the S3 bucket.

## Setting up a new development tag
1. Name the branch exactly as the new version with  (e.g. v1.4.5-alpha10)
2. Search and replace all occurances of the old branch to the new (e.g. v1.4.2-alpha9 == replace with ==> v1.4.5-alpha10)
3. Files under "runner_configs" use raw file retrieval from gitlab to pull these files, if they might change on this branch, the retrieval must be updated to isolate to the branch by replacing occurances of `/-/raw/main/` with `/-/raw/v1.4.5-alpha10/`
4. In the public S3 bucket that houses the templates, create a new version key (subdirectory) with the same name (e.g. v1.4.5-alpha10)

## Releasing
1. Ensure that 5ASGAutoScalingMaxSize, Default: 20 is set - to prevent overrun of tests against Gitlab.com
1. Merge to main WITHOUT deleting the branch.  If you accidentally delete it, immediately recreate it from the merge to main.
2. Apply the git tag "latest" to this version on the local git repository and force push tags.
3. Create a GitLab release and tag from the default branch using the version tag.
4. Merge to any special releases WITHOUT deleting the branch (e.g. "experimental" for the experiment that links GitLab Runner UI to this project).


Technically when files are loaded from main (like easy button markdowns or cloudformation templates) - key parts are pointing to the branch and the S3 url by the same name. The reference to the runner script will refer back to the branch you merged from.
