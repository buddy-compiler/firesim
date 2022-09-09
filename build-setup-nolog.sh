#!/usr/bin/env bash

# FireSim initial setup script. Under FireSim-as-top this script will:
# 1) Initalize submodules (only the required ones, minimizing duplicates
# 2) Install RISC-V tools, including linux tools
# 3) Installs python requirements for firesim manager

# Under library mode, (2) is skipped.

# TODO: build FireSim linux distro here?

# exit script if any command fails
set -e
set -o pipefail

unamestr=$(uname)
RDIR=$(pwd)

FASTINSTALL=false
IS_LIBRARY=false
SKIP_TOOLCHAIN=false
SKIP_VALIDATE=false
TOOLCHAIN=riscv-tools
USE_PINNED_DEPS=true
ENV_NAME=firesim

function usage
{
    echo "usage: build-setup.sh [OPTIONS] [riscv-tools | esp-tools]"
    echo "warning: The user must define $RISCV in their env to provide their own cross-compiler + sysroot."
    echo "installation types:"
    echo "   riscv-tools: if set, builds the riscv toolchain collateral (this is the default)"
    echo "   esp-tools: if set, builds the esp toolchain collateral used for the hwacha/gemmini accelerators"
    echo "options:"
    echo "   --skip-toolchain: if set, skips building extra RISC-V toolchain collateral i.e Spike,"
    echo "                   PK, RISC-V tests, libgloss and installing it to $RISCV (including cloning or building)."
    echo "   --library: if set, initializes submodules assuming FireSim is being used"
    echo "            as a library submodule. Implies --skip-toolchain "
    echo "   --skip-validate: if set, skips checking if user is on release tagged branch"
    echo "   --unpinned-deps: if set, use unpinned conda package dependencies"
}

if [ "$1" == "--help" -o "$1" == "-h" -o "$1" == "-H" ]; then
    usage
    exit 3
fi

while test $# -gt 0
do
   case "$1" in
        --library)
            IS_LIBRARY=true;
            SKIP_TOOLCHAIN=true;
            ;;
        --skip-toolchain)
            SKIP_TOOLCHAIN=true;
            ;;
        --skip-validate)
            SKIP_VALIDATE=true;
            ;;
        riscv-tools | esp-tools)
            TOOLCHAIN=$1;
            ;;
        --unpinned-deps)
            USE_PINNED_DEPS=false;
            ;;
        -h | -H | --help)
            usage
            exit
            ;;
        --*) echo "ERROR: bad option $1"
            usage
            exit 1
            ;;
        *) echo "ERROR: bad argument $1"
            usage
            exit 2
            ;;
    esac
    shift
done

# before doing anything verify that you are on a release branch/tag
set +e
tag=$(git describe --exact-match --tags)
tag_ret_code=$?
set -e
if [ $tag_ret_code -ne 0 ]; then
    if [ "$SKIP_VALIDATE" = false ]; then
        read -p "WARNING: You are not on an official release of FireSim."$'\n'"Type \"y\" to continue if this is intended, otherwise see https://docs.fires.im/en/stable/Initial-Setup/Setting-up-your-Manager-Instance.html#setting-up-the-firesim-repo: " validate
        [[ $validate == [yY] ]] || exit 5
        echo "Setting up non-official FireSim release"
    fi
else
    echo "Setting up official FireSim release: $tag"
fi

if [ -z "$RISCV" ]; then
    echo "ERROR: You must set the RISCV environment variable before running."
    exit 4
else
    echo "Using existing RISCV toolchain at $RISCV"
fi

# Remove and backup the existing env.sh if it exists
# The existing of env.sh implies this script completely correctly
if [ -f env.sh ]; then
    mv -f env.sh env.sh.backup
fi


# This will be flushed out into a complete env.sh which will be written out
# upon completion.
env_string="# This file was generated by $0"

function env_append {
    env_string+=$(printf "\n$1")
}

# Initially, create a env.sh that suggests build.sh did not run correctly.
bad_env="${env_string}
echo \"ERROR: build-setup.sh did not execute correctly or was terminated prematurely.\"
echo \"Please review build-setup-log for more information.\"
return 1"
echo "$bad_env" > env.sh

env_append "export FIRESIM_ENV_SOURCED=1"

git config submodule.target-design/chipyard.update none
git submodule update --init --recursive #--jobs 8

if [ "$IS_LIBRARY" = false ]; then
    # This checks if firemarshal has already been configured by someone. If
    # not, we will provide our own config. This must be checked before calling
    # init-submodules-no-riscv-tools.sh because that will configure
    # firemarshal.
    marshal_cfg=$RDIR/target-design/chipyard/software/firemarshal/marshal-config.yaml
    if [ ! -f $marshal_cfg ]; then
      first_init=true
    else
      first_init=false
    fi

    git config --unset submodule.target-design/chipyard.update
    git submodule update --init target-design/chipyard
    cd $RDIR/target-design/chipyard

    ./scripts/init-submodules-no-riscv-tools.sh --skip-validate
    # Deinitialize Chipyard's FireSim submodule so that fuzzy finders, IDEs,
    # etc., don't get confused by source duplication.
    git submodule deinit sims/firesim
    cd $RDIR

    # Configure firemarshal to know where our firesim installation is.
    # If this is a fresh init of chipyard, we can safely overwrite the marshal
    # config, otherwise we have to assume the user might have changed it
    if [ $first_init = true ]; then
      echo "firesim-dir: '../../../../'" > $marshal_cfg
    fi
    env_append "export FIRESIM_STANDALONE=1"
fi

# FireMarshal Setup
if [ "$IS_LIBRARY" = true ]; then
    target_chipyard_dir=$RDIR/../..

    # setup marshal symlink
    ln -sf ../../../software/firemarshal $RDIR/sw/firesim-software
else
    target_chipyard_dir=$RDIR/target-design/chipyard

    # setup marshal symlink
    ln -sf ../target-design/chipyard/software/firemarshal $RDIR/sw/firesim-software
fi

# Conda Setup
if [ "$IS_LIBRARY" = true ]; then
    # the chipyard conda environment should be installed already and be sufficient
    if [ -z ${CONDA_DEFAULT_ENV+x} ]; then
        echo "ERROR: No conda environment detected. If using Chipyard, did you source 'env.sh'."
        exit 5
    fi
else
    # note: lock file must end in .conda-lock.yml - see https://github.com/conda-incubator/conda-lock/issues/154
    LOCKFILE=$RDIR/conda-requirements-$TOOLCHAIN-linux-64.conda-lock.yml
    YAMLFILE=$RDIR/conda-requirements-$TOOLCHAIN.yaml
    if [ "$USE_PINNED_DEPS" = true ]; then
        # use conda-lock to create env
        conda-lock install -n $ENV_NAME $LOCKFILE
    else
        # auto-gen the lockfile
        conda-lock -f $YAMLFILE -p linux-64 --lockfile $LOCKFILE
        # use conda-lock to create env
        conda-lock install -n $ENV_NAME $LOCKFILE
    fi
    env_append "conda activate $ENV_NAME"
fi

# RISC-V Toolchain Compilation
if [ "$SKIP_TOOLCHAIN" != true ]; then
    $target_chipyard_dir/scripts/build-toolchain-extra.sh --skip-validate $TOOLCHAIN
fi

cd $RDIR

# commands to run only on EC2
# see if the instance info page exists. if not, we are not on ec2.
# this is one of the few methods that works without sudo
if wget -T 1 -t 3 -O /dev/null http://169.254.169.254/; then

    (

	# ensure that we're using the system toolchain to build the kernel modules
	# newer gcc has --enable-default-pie and older kernels think the compiler
	# is broken unless you pass -fno-pie but then I was encountering a weird
	# error about string.h not being found
	export PATH=/usr/bin:$PATH

	cd "$RDIR/platforms/f1/aws-fpga/sdk/linux_kernel_drivers/xdma"
	make

	# Install firesim-software dependencies
	# We always setup the symlink correctly above, so use sw/firesim-software
	marshal_dir=$RDIR/sw/firesim-software
	# the only ones missing are libguestfs-tools
	sudo yum install -y libguestfs-tools bc

	# Setup for using qcow2 images
	cd $RDIR
	./scripts/install-nbd-kmod.sh

    )

    (
	if [[ "${CPPFLAGS:-zzz}" != "zzz" ]]; then
	    # don't set it if it isn't already set but strip out -DNDEBUG because
	    # the sdk software has assertion-only variable usage that will end up erroring
	    # under NDEBUG with -Wall and -Werror
	    export CPPFLAGS="${CPPFLAGS/-DNDEBUG/}"
	fi


	# Source {sdk,hdk}_setup.sh once on this machine to build aws libraries and
	# pull down some IP, so we don't have to waste time doing it each time on
	# worker instances
	AWSFPGA=$RDIR/platforms/f1/aws-fpga
	cd $AWSFPGA
	bash -c "source ./sdk_setup.sh"
	bash -c "source ./hdk_setup.sh"
    )

fi

cd $RDIR
set +e
./gen-tags.sh
set -e



read -r -d '\0' NDEBUG_CHECK <<'END_NDEBUG'
# Ensure that we don't have -DNDEBUG anywhere in our environment

# check and fixup the known place where conda will put it
if [[ "$CPPFLAGS" == *"-DNDEBUG"* ]]; then
    echo "::INFO:: removing '-DNDEBUG' from CPPFLAGS as we prefer to leave assertions in place"
    export CPPFLAGS="${CPPFLAGS/-DNDEBUG/}"
fi

# check for any other occurances and warn the user
env | grep -v 'CONDA_.*_BACKUP' | grep -- -DNDEBUG && echo "::WARNING:: you still seem to have -DNDEBUG in your environment. This is known to cause problems."
true # ensure env.sh exits 0
\0
END_NDEBUG
env_append "$NDEBUG_CHECK"

# Write out the generated env.sh indicating successful completion.
echo "$env_string" > env.sh

echo "Setup complete!"
echo "To generate simulator RTL and run sw-RTL simulation, source env.sh"
echo "To use the manager to deploy builds/simulations on EC2, source sourceme-f1-manager.sh to setup your environment."
echo "To run builds/simulations manually on this machine, source sourceme-f1-full.sh to setup your environment."
