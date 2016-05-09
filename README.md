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
    config.slack_build_channel = '#slack-channel' # Or 'private-channel' (no hash sign)
    config.slack_builders = ['@bill', '@ben', '@daisy']
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

As soon as you save the webhook it will send a `ping` message to the `build-buddy` service.  You should get a 200 reponse.  If you do then congratulations, everything is ready to go with GitHub.

### MongoDB

Finally, build-buddy can be configured to write build metrics to a MongoDB.  # Installing MongoDB on OS X

To install MongoDB on OS X using `launchd` follow these steps:

Install with Homebrew with SSL/TLS support:

```bash
brew install mongodb --with-openssl
```

This may grumble a about OpenSSL and OS X.  Just follow the instructions that `brew` gives.  

Then, switch to super user mode:

```bash
sudo -s
```

First we need to create a `_mongodb` user and group:

```bash
dscl
cd /Local/Default
ls Groups gid
```

Find a group id that is not in use under 500, e.g. 300.  Then:

```bash
create Groups/_mongodb
create Groups/_mongodb PrimaryGroupID 300
ls Users uid
```

Find a user id that is available under 500, e.g. 300.  Then:

```bash
create Users/_mongodb UniqueID 300
create Users/_mongodb PrimaryGroupID 300
create Users/_mongodb UserShell /usr/bin/false
create Users/_mongodb NFSHomeDirectory /var/empty
```

This creates a user with no HOME directory and no shell.  Now add the user to the `_mongodb` group:

```bash
append Groups/_mongodb GroupMembership _mongodb
exit
```

Finally, stop the user from showing up on the login screen with:

```bash
dscl . delete /Users/_mongodb AuthenticationAuthority
dscl . create /Users/_mongodb Password "*"
```

Now create the database and log file directories and assign ownership to the `_mongodb` user:

```bash
mkdir -p /var/lib/mongodb
chown _mongodb:_mongodb /var/lib/mongodb
mkdir -p /var/log/mongodb
chown _mongodb:_mongodb /var/log/mongodb
```

Create a `/etc/mongod.conf` file and put the following in it:

```
systemLog:
  destination: file
  path: "/var/log/mongodb/mongodb.log"

storage:
  dbPath: "/var/lib/mongodb"

net:
  port: 27017
  bindIp: 127.0.0.1  # Or leave this out if you are allowing access outside the build machine
  ssl:
    mode: requireSSL
    PEMKeyFile: "/etc/ssl/your-domain.pem"
    CAFile: "/etc/ssl/your-domain.chain.pem"

security:
  authorization: disabled  # Or set a password if you desire. See the MongoDB site for more info.
```

You can get the `.pem` files in various ways.  If you already have a certificate and private key in your keychain for the OS X machine, you can export them to a `.p12` and run:

```bash
openssl pkcs12 -in your-domain.p12 -out your-domain.pem -nodes
```

You can do the same for the root certificate authority certificate chain which should also be in the OS X system keychain.

After you've had some fun with SSL, it's now time to create a `/Library/LaunchDaemons/org.mongo.mongod.plist` file and put the following in it:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>org.mongo.mongod</string>
    <key>RunAtLoad</key>
    <true/>
    <key>ProgramArguments</key>
    <array>
      <string>/usr/local/bin/mongod</string>
      <string>--config</string>
      <string>/etc/mongod.conf</string>
    </array>
    <key>UserName</key>
    <string>_mongodb</string>
    <key>GroupName</key>
    <string>_mongodb</string>
    <key>InitGroups</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>HardResourceLimits</key>
    <dict>
      <key>NumberOfFiles</key>
      <integer>4096</integer>
    </dict>
    <key>SoftResourceLimits</key>
    <dict>
      <key>NumberOfFiles</key>
      <integer>4096</integer>
    </dict>
  </dict>
</plist>
```

Finally, start the `mongod` daemon with:

```bash
launchctl load /Library/LaunchDaemons/org.mongo.mongod.plist
```

Note, if you ever need to manually start/stop the `mongod` service **DON'T** do it as `root` using `sudo` or your MongoDB log files will not be overwritable by `mongod` when it restarts.  Instead, run the `mongod` command as the `_mongodb` user and group with:

```bash
sudo -u _mongodb -g _mongodb /usr/local/bin/mongod --config /etc/mongod.conf
```
You can ensure that MongoDB is running by checking the log in the **Console** app and running the `mongo` command line tool.  [RoboMongo](https://robomongo.org/) is a good GUI tool to use for general interaction.
