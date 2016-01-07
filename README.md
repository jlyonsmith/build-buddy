## Generating Secret Token

You can generate a new secret token for GitHub to use when calculating the web hook hash with:

 ```bash
 ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
 ```

## Pull Request Build

Happens on each pull request or commit to the `master` branch.

- Started by PR from Git web hook or Slackbot
- Aborts if build one already running
- Updates commit status on GitHub
- Deletes and re-creates a build directory
- Installs Gems and Cocoapods
- Runs unit and UI tests on two or three platforms
- Responds to web hook
- Notify Slack channel of outcome

## Internal Builds

Happens nightly on the `master` branch.
Uses Apple launch agent to invoke Slackbot to start a build even night

- Wait for Slackbot to kick off a build
- Don't start if one already running (just tell the user)
- Create a clean directory
- Ensure Gems and Cocoapods installed
- Ensure code is in internal mode
- Replace tabs with spaces in source
- Fix any end of line issues in source code
- Pull updated provisioning profile from Apple
- Ensure correct signing certificates are available
- Update the build tag including adding bug fixes to commit message
- Run tests on more platforms (How many?)
- Generate code coverage data (How to share?)
- Upload the archive and dSYM to [Crashlytics] (http://support.crashlytics.com/knowledgebase/articles/370383-beta-distribution-with-ios-build-servers)
- Notify appropriate Slack channel of the outcome

## External Builds

Happens on demand on the `vM.m`, release staging branch.

- Wait for ping from Slackbot to start a build
- Don't start if one already running
- Create a clean directory
- Ensure Gems and Cocoapods installed
- Ensure code is in non-internal mode
- Work on a specific pre-release branch that is passed in (check Git for available branches)
- Pull updated provisioning profile from Apple
- Ensure correct signing certificates are available
- Update the build tag including adding bug fixes to commit message
- Ensure that TestFlight record exists for the new version
- Upload the archive to TestFlight
- Upload the archive and dSYM Crashlytics
- Notify Slack end email if failure
