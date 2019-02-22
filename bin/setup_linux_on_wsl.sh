#!/bin/bash
set -x

export CF_DEPLOYMENT_VERSION=v4.2.0
export SCRIPT="$( basename "${BASH_SOURCE[0]}" )"
export SCRIPTPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SCRIPT_GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$SCRIPT_GIT_BRANCH" != "HEAD" ]; then
    SCRIPT_GIT_REMOTE="$(git config --local --get branch.$SCRIPT_GIT_BRANCH.remote)"
    SCRIPT_GIT_REPO_BASE="$(git config --local --get remote.$SCRIPT_GIT_REMOTE.url | sed -E 's/\/[A-Za-z0-9-]+\.git//g')"
else
    SCRIPT_GIT_REPO_BASE="https://github.com/SolaceLabs"
fi


export WIN_DRIVE=${WIN_DRIVE:-"/mnt/c"}
export VIRTUALBOX_HOME=${VIRTUALBOX_HOME:-"$WIN_DRIVE/Program Files/Oracle/VirtualBox"}
export GIT_REPO_BASE=${GIT_REPO_BASE:-"$SCRIPT_GIT_REPO_BASE"}
export WORKSPACE=${WORKSPACE:-$HOME/workspace}
export SETTINGS_FILE=${SETTINGS_FILE:-$HOME/.settings.sh}
export REPOS_DIR=${REPOS_DIR:-$HOME/repos}

SETUP_LOG_FILE=${SETUP_LOG_FILE:-"$WORKSPACE/$SCRIPT.log"}

# vboxmanage has to be able to see $HOME/.bosh_virtualbox_cpi in the Windows filesystem.
# Therefore we create the files there, and link to them from the Linux home.
function setupLinks() {
    if [ ! -e $HOME/.bosh_virtualbox_cpi ]; then
        mkdir -p $WIN_DRIVE$HOME/.bosh_virtualbox_cpi
        ln -s $WIN_DRIVE$HOME/.bosh_virtualbox_cpi $HOME/.bosh_virtualbox_cpi
    fi

    if [ ! -e /usr/local/bin/VBoxManage ]; then
        sudo ln -s "$VIRTUALBOX_HOME/VBoxManage.exe" /usr/local/bin/VBoxManage
        sudo ln -s "$VIRTUALBOX_HOME/VBoxManage.exe" /usr/local/bin/vboxmanage
    fi
}

function cloneRepo() {
    if [ ! -d $REPOS_DIR ]; then
        mkdir $REPOS_DIR
    fi
    (
        cd $REPOS_DIR
        if [ ! -d solace-messaging-cf-dev ]; then
        (
            git clone $GIT_REPO_BASE/solace-messaging-cf-dev.git
            cd solace-messaging-cf-dev
            if [ ! -z $BRANCH ]; then
                git checkout $BRANCH
            fi
        )
        fi

        if [ ! -f solace-messaging-cf-dev/cf-solace-messaging-deployment/README.md ]; then
        (
            cd solace-messaging-cf-dev
            git clone $GIT_REPO_BASE/cf-solace-messaging-deployment.git
            cd cf-solace-messaging-deployment
            if [ ! -z $BRANCH ]; then
                git checkout $BRANCH
            fi
        )
        fi
    )
}

function installBosh() {
    $REPOS_DIR/solace-messaging-cf-dev/bin/bosh_lite_vm.sh -c
    if [ ! -e /usr/local/bin/bosh ]; then
        sudo cp $REPOS_DIR/solace-messaging-cf-dev/bucc/bin/bosh /usr/local/bin
    fi
}

function deployCf() {
    source $WORKSPACE/bosh_env.sh
    $REPOS_DIR/solace-messaging-cf-dev/bin/cf_deploy.sh
}

function installPrograms() {

    if [ ! -e /usr/local/bin/cf ]; then
        # Install the cf cli tool.
        curl -L "https://packages.cloudfoundry.org/stable?release=linux64-binary&source=github" | tar -zx
        sudo mv cf /usr/local/bin

        sudo apt-get update

        sudo apt-get install -y jq build-essential zlibc zlib1g-dev ruby ruby-dev rubygems openssl libssl-dev libxslt-dev libxml2-dev libreadline-dev libyaml-dev libsqlite3-dev sqlite3
        sudo gem install bundler
    fi
}

function getSettingsEnv() {
    echo "export SOLACE_MESSAGING_CF_DEV=$REPOS_DIR/solace-messaging-cf-dev"
    echo "export WORKSPACE=$WORKSPACE"
    echo "export PATH=\$PATH:\$SOLACE_MESSAGING_CF_DEV/bucc/bin"
}

function createSettingsFile() {

	if [ ! -f $SETTINGS_FILE ]; then
		echo "Capturing settings in $SETTINGS_FILE"
	        getSettingsEnv >> $SETTINGS_FILE
	fi
}

function alterProfile() {
    NUM_LINES=$( grep -c "source $SETTINGS_FILE" ~/.profile )

    if [ "$NUM_LINES" -eq 0 ]; then
        read -p "Would you like  your .profile modified to automatically set up the CF environment when you next log in? (yN): "

        if [[ $REPLY =~ ^[Yy] ]]; then
            echo "source $SETTINGS_FILE" >> ~/.profile
            echo "source $REPOS_DIR/solace-messaging-cf-dev/.profile" >> ~/.profile
        fi
    fi
}

function logFailedStep() {
    echo "Step $currentStep FAILED"
    exit 1
}


environmentSetup=false
runInstallBosh=false
runDeployCf=false
postSetup=false
currentStep=""

function setAllStepsTrue() {
    environmentSetup=true
    runInstallBosh=true
    runDeployCf=true
    postSetup=true
}

function setupLinuxOnWsl() {

    cd
    trap 'logFailedStep' ERR EXIT
    
    if [ "$environmentSetup" = true ]; then
        currentStep="-e Environment Setup"
        setupLinks
        installPrograms
        cloneRepo
    fi

    if [ "$runInstallBosh" = true ]; then
        currentStep="-b Install Bosh"
        installBosh
    fi

    if [ "$runDeployCf" = true ]; then
        currentStep="-c Deploy Cloud Foundary"
        deployCf
    fi

    if [ "$postSetup" = true ]; then
        currentStep="-p Post setup"
        createSettingsFile
        alterProfile
    fi

}


#### 

function help() {
    echo "-h | --help Print this help menu."
    echo "-a | --all Runs full script including environment setup, BOSH installation, cloudFoundary
    deployment, and post setup tasks."
    echo "-e | --environment Sets up pre environment before BOSH installation."
    echo "-b | --installBosh Runs BOSH installation."
    echo "-c | --deployCf Deploys cloudFoundary."
    echo "-p | --postSetup Runs post setup tasks."
}

function parseArgs() {
# Parse Command line arguments and determine which functions to run

    POSITIONAL=()
    if [ "$#" -eq 0 ]; then
        setAllStepsTrue
        return
    fi

    while [[ $# -gt 0 ]]
        do
            key="$1"
            case $key in
            -a|--all)
            setAllStepsTrue
            shift
            ;;
            -e|--environment)
            environmentSetup=true
            shift
            ;;
            -b|--installBosh)
            runInstallBosh=true
            shift
            ;;
            -c|--deployCf)
            runDeployCf=true
            shift
            ;;
            -p|--postSetup)
            postSetup=true
            shift
            ;;
            -h|--help)
            help
            exit 0
            shift
            ;;

            --default)
            help
            exit 0
            shift
            ;;
            *)
            help
            exit 0
            POSITIONAL+=("$1")
            shift
            ;;
        esac
    done
    set -- "${POSITIONAL[@]}"
}

parseArgs "$@"
setupLinuxOnWsl | tee $SETUP_LOG_FILE

echo "Setup log file: $SETUP_LOG_FILE"
