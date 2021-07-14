
# Branch Testing Before Merging to Main

## Setting up a new development branch
1. Name the branch exactly as the new version with  (e.g. v1.4.8-alpha13)
2. Search and replace all occurances of the old branch to the new (e.g. v1.4.2-alpha9 == replace with ==> v1.4.5-alpha10)
3. Files under "runner_configs" use raw file retrieval from gitlab to pull these files, if they might change on this branch, the retrieval must be updated to isolate to the branch by replacing occurences of the last version (e.g. `/v1.4.8-alpha13/`) with the next version (e.g. `/v1.4.5-alpha10/`)
4. In the public S3 bucket that houses the templates, create a new version key (subdirectory) with the same name (e.g. v1.4.8-alpha13)

## Releasing
1. Ensure that 5ASGAutoScalingMaxSize, Default: 20 is set - to prevent overrun of tests against Gitlab.com
1. Merge to main WITHOUT deleting the branch.  If you accidentally delete it, immediately recreate it from the merge to main.
2. Apply the git tag "latest" to this version on the local git repository and force push tags.
3. Create a GitLab release and tag from the default branch using the version tag.
4. Merge to any special releases WITHOUT deleting the branch (e.g. "experimental" for the experiment that links GitLab Runner UI to this project).


Technically when files are loaded from main (like easy button markdowns or cloudformation templates) - key parts are pointing to the branch and the S3 url by the same name. The reference to the runner script will refer back to the branch you merged from.