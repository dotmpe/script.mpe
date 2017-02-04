#!/usr/bin/env bash

set -e

test -z "$Build_Debug" || set -x

test -z "$Build_Deps_Default_Paths" || {

  test -n "$SRC_PREFIX" || {
    test -w /src/ \
      && SRC_PREFIX=/src/ \
      || SRC_PREFIX=$HOME/build
  }

  test -n "$PREFIX" || {
    test -w /usr/local/ \
      && PREFIX=/usr/local/ \
      || PREFIX=$HOME/.local
  }

  echo "Setting default paths: SRC_PREFIX=$SRC_PREFIX PREFIX=$PREFIX" >&2
}

test -n "$sudo" || sudo=
test -z "$sudo" || pref="sudo $pref"
test -z "$dry_run" || pref="echo $pref"

test -w /usr/local || {
  test -n "$sudo" || pip_flags=--user
  test -n "$sudo" || py_setup_f="--user"
}


test -n "$SRC_PREFIX" || {
  echo "Not sure where to checkout (SRC_PREFIX missing)" >&2
  exit 1
}

test -n "$PREFIX" || {
  echo "Not sure where to install (PREFIX missing)" >&2
  exit 1
}

test -d $SRC_PREFIX || ${pref} mkdir -vp $SRC_PREFIX
test -d $PREFIX || ${pref} mkdir -vp $PREFIX


install_bats()
{
  echo "Installing bats"
  test -n "$BATS_BRANCH" || BATS_BRANCH=master
  test -n "$BATS_REPO" || BATS_REPO=https://github.com/dotmpe/bats.git
  test -n "$BATS_BRANCH" || BATS_BRANCH=master
  test -d $SRC_PREFIX/bats || {
    git clone $BATS_REPO $SRC_PREFIX/bats || return $?
  }
  (
    cd $SRC_PREFIX/bats
    git checkout $BATS_BRANCH
    ${pref} ./install.sh $PREFIX
  )
}

install_composer()
{
  test -e ~/.local/bin/composer || {
    curl -sS https://getcomposer.org/installer |
      php -- --install-dir=$HOME/.local/bin --filename=composer
  }
  ~/.local/bin/composer --version
  test -x "$(which composer)" || {
    echo "Composer is installed but not found on PATH! Aborted. " >&2
    return 1
  }
  composer install
}

install_docopt()
{
  test -n "$install_f" || install_f="$py_setup_f"
  git clone https://github.com/dotmpe/docopt-mpe.git $SRC_PREFIX/docopt-mpe
  ( cd $SRC_PREFIX/docopt-mpe \
      && git checkout 0.6.x \
      && $pref python ./setup.py install $install_f )
}

install_git_versioning()
{
  git clone https://github.com/dotmpe/git-versioning.git $SRC_PREFIX/git-versioning
  ( cd $SRC_PREFIX/git-versioning && ./configure.sh $PREFIX && ENV=production ./install.sh )
}

install_mkdoc()
{
  test -n "$MKDOC_BRANCH" || MKDOC_BRANCH=master
  echo "Installing mkdoc ($MKDOC_BRANCH)"
  (
    cd $SRC_PREFIX
    test -e mkdoc ||
      git clone https://github.com/dotmpe/mkdoc.git
    cd mkdoc
    git checkout $MKDOC_BRANCH
    ./configure $PREFIX && ./install.sh
  )
  rm Makefile || printf ""
  ln -s $PREFIX/share/mkdoc/Mkdoc-full.mk Makefile
}

install_pylib()
{
  # for travis container build:
  pylibdir=$HOME/.local/lib/python2.7/site-packages
  test -n "$hostname" || hostname="$(hostname -s | tr 'A-Z' 'a-z')"
  case "$hostname" in
      simza )
          pylibdir=~/lib/py ;;
  esac
  # hack py lib here
  mkdir -vp $pylibdir
  test -e $pylibdir/script_mpe || {
    cwd=$(pwd)/
    pushd $pylibdir
    pwd -P
    ln -s $cwd script_mpe
    popd
  }
  export PYTHONPATH=$PYTHONPATH:.:$pylibdir/
}

install_apenwarr_redo()
{
  test -n "$global" || {
    test -n "$sudo" && global=1 || global=0
  }

  test $global -eq 1 && {

    test -d /usr/local/lib/python2.7/site-packages/redo \
      || {

        $pref git clone https://github.com/apenwarr/redo.git \
            /usr/local/lib/python2.7/site-packages/redo || return 1
      }

    test -h /usr/local/bin/redo \
      || {

        $pref ln -s /usr/local/lib/python2.7/site-packages/redo/redo \
            /usr/local/bin/redo || return 1
      }

  } || {

    which basher 2>/dev/null >&2 && {

      basher install apenwarr/redo
    } || {

      echo "Need basher to install apenwarr/redo locally" >&2
      return 1
    }
  }
}

install_git_lfs()
{
  # XXX: for debian only, and requires sudo
  test -n "$sudo" || {
    error "sudo required for GIT lfs"
    return 1
  }
  curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
  $pref apt-get install git-lfs
  # TODO: must be in repo. git lfs install
}

install_script()
{
  cwd=$(pwd)
  test -e $HOME/bin || ln -s $cwd $HOME/bin
  echo "install-script pwd=$cwd"
  echo "install-script bats=$(which bats)"
}


main_entry()
{
  test -n "$1" || set -- all

  case "$1" in all|project|git )
      git --version >/dev/null || {
        echo "Sorry, GIT is a pre-requisite"; exit 1; }
      which pip >/dev/null || {
        cd /tmp/ && wget https://bootstrap.pypa.io/get-pip.py && python get-pip.py; }
      pip install --user setuptools objectpath ruamel.yaml \
        || exit $?
      pip install -r test-requirements.txt
    ;; esac

  case "$1" in all|build|test|sh-test|bats )
      test -x "$(which bats)" || { install_bats || return $?; }
      PATH=$PATH:$PREFIX/bin bats --version
    ;; esac

  case "$1" in all|dev|build|check|test|git-versioning )
      test -x "$(which git-versioning)" || {
        install_git_versioning || return $?; }
    ;; esac

  case "$1" in all|python|project|docopt)
      # Using import seems more robust than scanning pip list
      python -c 'import docopt' || { install_docopt || return $?; }
    ;; esac

  case "$1" in npm|redmine|tasks)
      npm install -g redmine-cli || return $?
    ;; esac

  case "$1" in redo )
      # TODO: fix for other python versions
      install_apenwarr_redo || return $?
    ;; esac

  case "$1" in all|mkdoc)
      test -e Makefile || \
        install_mkdoc || return $?
    ;; esac

  case "$1" in all|pylib)
      install_pylib || return $?
    ;; esac

  case "$1" in all|script)
      install_script || return $?
    ;; esac

  case "$1" in all|project|git|git-lfs )
      # TODO: install_git_lfs
    ;; esac

  case "$1" in all|php|composer)
      test -x "$(which composer)" \
        || install_composer || return $?
    ;; esac

  test -d ~/.basher ||
    git clone git@github.com:basherpm/basher.git ~/.basher/

  test -x "$(which tap-to-junit-xml)" ||
    basher install jmason/tap-to-junit-xml

  echo "OK. All pre-requisites for '$1' checked"
}

test "$(basename $0)" = "install-dependencies.sh" && {
  test -n "$1" || set -- all
  while test -n "$1"
  do
    main_entry "$1" || exit $?
    shift
  done
} || printf ""

# Id: script-mpe/0 install-dependencies.sh
