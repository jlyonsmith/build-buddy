# Build Buddy

Build buddy an automated bot that does _buddy builds_ of your software for you.  It's controlled by Slack and GitHub pull requests.

## Setup

### Ruby

I recommend installing [Homebrew](http://brew.sh) to install either `rbenv` or `rvm` as is your preference.  NOTE: I only use `rbenv` so you may encounter issues with `rvm`.  The project requires ruby 2.2.2.

If you are using `rbenv` I recommend installing `rbenv-bundler` with `brew` to avoid the need to remember to type `bundle exec` to use local configured Gems.

### Installation

Install the Build Buddy Gem using:

```bash
gem install build-buddy
```

Before you do anything create a `.bbconfig` file with the following format:

```ruby
BuildBuddy.configure do |config|
    config.github_webhook_secret_token = '...'
    config.github_webhook_repo_full_name = 'RepoOwner/RepoName'
    config.github_api_token = '...'

    config.slack_api_token = '...'
    config.slack_build_channel = "slack-channel"

    config.build_log_dir = "logs/"

    config.pull_request_build_script = "scripts/pull_request_build.sh"
    config.master_build_script = "scripts/master_build.sh"
    config.release_build_script = "scripts/release_build.sh"
end
```

Create `scripts` directory and copy in the sample scripts from the `scripts/test/...` directory in this repository.  You'll eventually create your own customized build scripts based on your project type, but for now these will let you test things out.

### Slack

Firstly, Set up a [Slack](https://slack.com) account for your organization. Navigating the Slack API configuration can be quite a challenge.  You'll be creating a bot as a custom integration to Slack.

1. In a web browser navigate to your-org.slack.com.
2. Go to to _Team Settings_ from the drop down menu from your organization name.
3. Select _Build your own_ in the top right corner.
4. On the "What will you build?" page, select "Make a Custom Integration".
5. Select **Bots** from the "Build a Custom Integration" menu.
6. Give the bot a **Username**.  Don't start it with an @ sign.
7. On the next screen, give the bot a description and copy the API token to the `.bbconfig` file as the `config.slack_api_token` value.

Now you have a build bot configured, start the `build-buddy` script. Next start a private conversation with your bot and ask it something like, "What is your status?"  Actually, it will response to just the words **status** and **help** too.

### GitHub

Next it's time to get GitHub integration working.  You'll need to generate a personal access token for the user that will be committing build tags and version updates for the build.  

1. Log in to GitHub as this user.  
2. Go to the drop down in the top right hand corner (the one with the user icon next to teh arrow) and select **Settings** from the menu.
3. Go to **Personal access tokens** and create a new token.
4. Give the token a name, including for example the machine the token is used on, the words "build-buddy", etc.. Select repo, public_repo, write:repo_hook, read:repo_hook and repo:status scopes, then **Generate token**
5. Copy the token on this screen into the `config.github_api_token` setting in the `.bbconfig`

Finally, you need to set up a webhook for pull-requests to the repository.  Generate a secret token to use in the webhook:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```
 
Next, do the following:

1. If your build machine is available on the Internet, punch a hole in your firewall and use that address for the webhook.  Otherwise install a tool like [ngrok](http://ngrok.com) in order to create a public endpoint that GitHub can send the web hook to.
2. Once you know the webhook endpoint endpoint, e.g. https://api.mydomain.com/, go to the master repo for the project (the one that all the forks will create pull request too) and select **Settings**
3. Enter the URL plus the path `/webhook`
4. Enter the secret token from above as the `config.github_webhook_secret_token` setting in the `.bbconfig` file.

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
