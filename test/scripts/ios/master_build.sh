#!/usr/bin/env bash
#
# Build script for Internal Build
#
PRODUCT_NAME=Company
GIT_REPO_USER=Company
GIT_REPO_NAME=consumer_mobile
BUILD_DIR=~/Builds
BRANCH=$1
XCODEBUILD=$(which xcodebuild)
SCHEME="Company"
SIMULATOR_CONFIG="platform=iOS Simulator,name=iPhone 6,OS=latest"

case "$BRANCH" in
  v2.1)
  ;;
master)
  ;;
.*)
  echo Usage: $(basename $0) [BRANCH] [--trial]
  exit 1
  ;;
esac

# Initialize
echo Creating $BUILD_DIR
mkdir -p ${BUILD_DIR}/${GIT_REPO_USER}
cd ${BUILD_DIR}/${GIT_REPO_USER}
GIT_CLONE_DIR=$BUILD_DIR/$GIT_REPO_USER/$GIT_REPO_NAME
if [[ -d $GIT_CLONE_DIR ]]; then
  echo Deleting $GIT_CLONE_DIR
  rm -rf $GIT_CLONE_DIR
fi

# Pull source
echo Pulling sources to ${BUILD_DIR}/${GIT_REPO_USER}/${GIT_REPO_NAME}
git clone git@github.com:${GIT_REPO_USER}/${GIT_REPO_NAME}.git ${GIT_REPO_NAME}

# Switch to correct branch
cd ${GIT_REPO_NAME}
git checkout $BRANCH

# Install Gemfile
echo Pulling Gemfile
bundler install

# Pull Dependencies
echo Pulling Cocopods
bundler exec pod install

# Update the version number
bundle exec vamper -u
TAG_NAME=$(cat ${PRODUCT_NAME}.tagname.txt)
TAG_DESCRIPTION=$(cat ${PRODUCT_NAME}.tagdesc.txt)
echo New version is $TAG_DESCRIPTION

# Test
# e.g.
if ! $XCODEBUILD -workspace Company.xcworkspace -scheme "$SCHEME" -sdk iphonesimulator -destination "$SIMULATOR_CONFIG" test; then
 echo ERROR: Tests failed
 exit 1
fi

# Build Archive
if ! $XCODEBUILD -workspace Company.xcworkspace -scheme "$SCHEME" archive; then
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

# Push the version number and tags unless this is a trial build
if [[ "$2" -ne "--trial" ]]; then
  git push --follow-tags
fi

