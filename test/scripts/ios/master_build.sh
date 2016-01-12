#!/usr/bin/env bash
#
# Build script for an iOS project master branch

# Passed in from Build Buddy
if [[ -z "$GIT_REPO_OWNER" || -z "$GIT_REPO_NAME" ]]; then
  echo Must set GIT_REPO_OWNER, GIT_REPO_NAME
  exit 1
fi
BRANCH=$1

# Configure these for your build
XCODE_WORKSPACE=${GIT_REPO_NAME}.xcworkspace
XCODE_TEST_SCHEME=${GIT_REPO_NAME}
XCODE_ARCHIVE_SCHEME=${GIT_REPO_NAME}
BUILD_DIR=~/Builds
SIMULATOR_CONFIG="platform=iOS Simulator,name=iPhone 6,OS=latest"
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
cd ${GIT_REPO_NAME}
git checkout master

# Install Gemfile
echo Pulling Gemfile
bundler install

# Pull Dependencies
echo Pulling Cocopods
bundler exec pod install

# Update the version number
mkdir Scratch
bundle exec vamper -u
TAG_NAME=$(cat Scratch/${GIT_REPO_NAME}.tagname.txt)
TAG_DESCRIPTION=$(cat Scratch/${GIT_REPO_NAME}.tagdesc.txt)
echo New version is $TAG_DESCRIPTION

# Test
if ! $XCODEBUILD -workspace $XCODE_WORKSPACE -scheme "$XCODE_TEST_SCHEME" -sdk iphonesimulator -destination "$SIMULATOR_CONFIG" test; then
 echo ERROR: Tests failed
 exit 1
fi

# Build Archive
if ! $XCODEBUILD -workspace $XCODE_WORKSPACE -scheme "$XCODE_ARCHIVE_SCHEME" archive; then
 echo ERROR: Archive build failed
 exit 1
fi

# List of fixes since last tag
LAST_TAG_NAME=$(git tag -l "${BRANCH}*" | tail -1)

if [[ -n "$LAST_TAG_NAME" ]]; then
  BUG_FIXES=$(git log --pretty=oneline ${LAST_TAG_NAME}..HEAD | egrep -io 'CM-[0-9]+' | tr '[:lower:]' '[:upper:]' | sort -u | tr "\\n" " ")
  echo Bugs fixed since ${LAST_TAG_NAME} - ${BUG_FIXES}
else
  echo First build on this branch
fi

# Commit version changes
git add :/
git commit -m "${TAG_DESCRIPTION}" -m "${BUG_FIXES}"

# Add the version tag
echo Adding tag \'${TAG_NAME}\'
git tag -a ${TAG_NAME} -m "${TAG_DESCRIPTION}"

git push --follow-tags
