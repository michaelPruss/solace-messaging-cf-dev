#!/bin/bash

# Cross-OS compatibility ( gsed )
[[ $(uname) == 'Darwin' ]] && {

   FOUND_GNU_SED=1
   sed --version > /dev/null 2>&1
   if [ $? == "0" ]; then
     # Find a sed gnu version
     sed --version | head -n 1 | grep -i gnu > /dev/null
     FOUND_GNU_SED=$?
   fi

   if [ "$FOUND_GNU_SED" == "1" ]; then
      which gsed > /dev/null || {
            echo 'ERROR: GNU utils required for Mac. You may use homebrew to install them: brew install coreutils gnu-sed'
            exit 1
      }
      shopt -s expand_aliases
      alias sed=`which gsed`
   fi
}

REQUIRED_TOOLS=${REQUIRED_TOOLS:-"jq curl cf git gem sort head tail wc basename dirname grep which mktemp unzip tar ruby bundle"}

function checkRequiredTools() {
 for REQUIRED_TOOL in $@; do
  which $REQUIRED_TOOL > /dev/null || {
	echo "ERROR: '$REQUIRED_TOOL' was not found. Please install it."
 	exit 1
  }
 done
}

checkRequiredTools $REQUIRED_TOOLS

