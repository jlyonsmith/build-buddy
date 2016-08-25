# Build Buddy

_Build Buddy_ is a daemon that does _buddy builds_ of your software for you.  It's controlled by Slack and GitHub pull requests.

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
  config.github_webhook_port = 4567
  config.github_webhook_secret_token = '...'
  config.github_webhook_repo_full_name = '.../...'
  config.github_api_token = '...'
  config.slack_api_token = '...'
  config.slack_test_channel = "#..."
  config.slack_build_channel = "#..."
  config.slack_builders = ['@...', '@...']
  config.build_log_dir = "$HOME/logs/"
  config.pull_request_build_script = "bin/pull-request-build"
  config.branch_build_script = "bin/branch-build"
  config.pull_request_root_dir = "$HOME/builds/pr"
  config.branch_root_dir = "$HOME/builds/branch"
  config.allowed_build_branches = ['v1.0']
  config.server_base_uri = "https://..."
  config.mongo_uri = "mongodb://localhost:27017/..."
end
```

Customize the build scripts based on your project type.

### Slack

Firstly, set up a [Slack](https://slack.com) account for your organization. Navigating the Slack API configuration can be quite a challenge.  You'll be creating a bot as a custom integration to Slack.

1. In a web browser, navigate to https://api.slack.com/bot-users
2. Click on the "creating a new bot user" button.
3. Give the bot an @ name, following the onscreen instructions.
4. On the next screen, give the bot a description and copy the API token to the `.bbconfig` file as the `config.slack_api_token` value.

Now you have a build bot configured, start the `build-buddy` script. Next start a private conversation with your bot and ask it something like, "What is your status?"  Actually, it will response to just the words **status** and **help** too.

### GitHub

Next it's time to get GitHub integration working.  You'll need to generate a personal access token for the user that will be committing build tags and version updates for the build.  

1. Log in to GitHub as the user that the build will be acting as. It's wise to create a user specifically for builds to avoid giving access to you personal GitHub account.
2. Go to the drop down in the top right hand corner (the one with the user icon, next to the arrow) and select **Settings** from the menu.
3. Go to **Personal access tokens** and create a new token.
4. Give the token a name, including for example the machine the token is used on, the words "build-buddy", etc.. Select repo, repo:status, repo_deployment, public_repo, write:repo_hook, read:repo_hook scopes, then **Generate token**
5. Copy the token on this screen into the `config.github_api_token` setting in the `.bbconfig`

Finally, you need to set up a webhook for pull-requests to the repository.  Do the steps:

1. In order for GitHub to send events to your `build-buddy` instance you must have an endpoint visible over the Internet.  I _highly_ recommend you only use HTTPS for the webhook events.  There are a couple of good ways to create the webhook endpoint:
    1. Install [ngrok](http://ngrok.com) in order to create a public endpoint that GitHub can send the web hook to.  Super easy and a great way to get started.  You configure ngrok to forward requests to `build-buddy` on your local machine.
    2. Use a web server such as [nginx](http://nginx.org) running on the same machine as `build-buddy` that can proxy the requests to `build-buddy`.  Instructions on how to configure nginx to that can be found in [nginx Configuration](https://github.com/jlyonsmith/HowTo/blob/master/nginx_configuration.md).
2. Once you know the webhook endpoint endpoint, e.g. https://api.mydomain.com/, go to the master repo for the project (the one that all the forks will create pull request too) and select **Settings**
3. Enter the URL plus the path `/webhook`
4. Create secret token using for use by the webhook.  This lets `build-buddy` know the call is actually from GitHub:

    ```bash
    ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
    ```
    Then, paste this token into the `.bbconfig` file under the `config.github_webhook_secret_token` setting.

As soon as you save the webhook it will send a `ping` message to the `build-buddy` service.  You should get a 200 reponse.  If you do then congratulations, everything is ready to go with GitHub.

### MongoDB

Finally, build-buddy can be configured to write build metrics to a MongoDB. Setting up MongoDB properly, with it's own user and group and password protected accounts, is straightforward but requires quite a few steps. Follow the instructions in [Installing MongoDB on macOS](https://github.com/jlyonsmith/HowTo/blob/master/Install_MongoDB_on_macOS.md).

Once you have MongoDB up and running, simply add an entry to the `.bbconfig` file:

```ruby
config.mongo_uri = "mongodb://user:password@localhost:27017/build-buddy"
```
