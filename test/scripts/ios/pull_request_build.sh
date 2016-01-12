#!/usr/bin/env bash
#
# Build script for an iOS project pull request

# Passed in from Build Buddy
if [[ -z "$GIT_REPO_OWNER" || -z "$GIT_REPO_NAME" || -z "$GIT_PULL_REQUEST" ]]; then
  echo Must set GIT_REPO_OWNER, GIT_REPO_NAME and GIT_PULL_REQUEST
  exit 1
fi

# Configurable for iOS Build
XCODE_WORKSPACE=${GIT_REPO_NAME}.xcworkspace
XCODE_TEST_SCHEME=${GIT_REPO_NAME}
SIMULATOR_CONFIG="platform=iOS Simulator,name=iPhone 6,OS=latest"
BUILD_DIR=~/Builds
XCODEBUILD=$(which xcodebuild)

# Initialize
echo Creating $BUILD_DIR
mkdir -p ${BUILD_DIR}/${GIT_REPO_OWNER}
cd ${BUILD_DIR}/${GIT_REPO_OWNER}
GIT_CLONE_DIR=$BUILD_DIR/$GIT_REPO_OWNER/$GIT_REPO_NAME
if [[ -d $GIT_CLONE_DIR ]]; then
  echo Deleting $GIT_CLONE_DIR
  rm -rf $GIT_CLONE_DIR
fi

# Pull source
echo Pulling sources to ${BUILD_DIR}/${GIT_REPO_OWNER}/${GIT_REPO_NAME}
git clone git@github.com:${GIT_REPO_OWNER}/${GIT_REPO_NAME}.git ${GIT_REPO_NAME}

# Switch to correct branch
# See https://gist.github.com/piscisaureus/3342247
cd ${GIT_REPO_NAME}
git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
git fetch origin
git checkout pr/$GIT_PULL_REQUEST

# Install Gemfile
echo Pulling Gemfile
bundle install

# Pull Dependencies
echo Pulling Cocopods
bundle exec pod install

# Test
if ! $XCODEBUILD -workspace ${XCODE_WORKSPACE} -scheme "$XCODE_TEST_SCHEME" -sdk iphonesimulator -destination "$SIMULATOR_CONFIG" test; then
 echo ERROR: Tests on \"$SIMULATOR_CONFIG\" failed
 exit 1
fi
