#!/usr/bin/env bash

# Convenience script to build Infer when using opam

# Copyright (c) 2015-present, Facebook, Inc.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -e
set -o pipefail
set -u

SCRIPT_DIR=&quot;$( cd &quot;$( dirname &quot;${BASH_SOURCE[0]}&quot; )&quot; &amp;&amp; pwd )&quot;
INFER_ROOT=&quot;$SCRIPT_DIR&quot;
PLATFORM=&quot;$(uname)&quot;
NCPU=&quot;$(getconf _NPROCESSORS_ONLN 2&gt;/dev/null || echo 1)&quot;
INFER_OPAM_DEFAULT_SWITCH=&quot;ocaml-variants.4.07.1+flambda&quot;
INFER_OPAM_SWITCH=${INFER_OPAM_SWITCH:-$INFER_OPAM_DEFAULT_SWITCH}

function usage() {
  echo &quot;Usage: $0 [-y] [targets]&quot;
  echo
  echo &quot; targets:&quot;
  echo &quot;   all      build everything (default)&quot;
  echo &quot;   clang    build C and Objective-C analyzer&quot;
  echo &quot;   java     build Java analyzer&quot;
  echo
  echo &quot; options:&quot;
  echo &quot;   -h,--help             show this message&quot;
  echo &quot;   --no-opam-lock        do not use the opam.locked file and let opam resolve dependencies&quot;
  echo &quot;   --only-setup-opam     initialize opam, install the opam dependencies of infer, and exit&quot;
  echo &quot;   --user-opam-switch    use the current opam switch to install infer (default: $INFER_OPAM_DEFAULT_SWITCH)&quot;
  echo &quot;   -y,--yes              automatically agree to everything&quot;
  echo
  echo &quot; examples:&quot;
  echo &quot;    $0               # build Java and C/Objective-C analyzers&quot;
  echo &quot;    $0 java clang    # equivalent way of doing the above&quot;
  echo &quot;    $0 java          # build only the Java analyzer&quot;
}

# arguments
BUILD_CLANG=${BUILD_CLANG:-no}
BUILD_JAVA=${BUILD_JAVA:-no}
INFER_CONFIGURE_OPTS=${INFER_CONFIGURE_OPTS:-&quot;&quot;}
INFER_OPAM_SWITCH=${INFER_OPAM_SWITCH:-$INFER_OPAM_SWITCH_DEFAULT}
INTERACTIVE=${INTERACTIVE:-yes}
JOBS=${JOBS:-$NCPU}
ONLY_SETUP_OPAM=${ONLY_SETUP_OPAM:-no}
USE_OPAM_LOCK=${USE_OPAM_LOCK:-yes}
USER_OPAM_SWITCH=no

ORIG_ARGS=&quot;$*&quot;

while [[ $# &gt; 0 ]]; do
  opt_key=&quot;$1&quot;
  case $opt_key in
    all)
      BUILD_CLANG=yes
      BUILD_JAVA=yes
      shift
      continue
      ;;
    clang)
      BUILD_CLANG=yes
      shift
      continue
      ;;
    java)
      BUILD_JAVA=yes
      shift
      continue
      ;;
    -h|--help)
      usage
      exit 0
     ;;
    --no-opam-lock)
      USE_OPAM_LOCK=no
      shift
      continue
     ;;
    --user-opam-switch)
      USER_OPAM_SWITCH=yes
      shift
      continue
     ;;
    --only-setup-opam)
      ONLY_SETUP_OPAM=yes
      shift
      continue
     ;;
    -y|--yes)
      INTERACTIVE=no
      shift
      continue
     ;;
     *)
      usage
      exit 1
  esac
  shift
done

# if no arguments then build both clang and Java
if [ &quot;$BUILD_CLANG&quot; == &quot;no&quot; ] &amp;&amp; [ &quot;$BUILD_JAVA&quot; == &quot;no&quot; ]; then
  BUILD_CLANG=yes
  BUILD_JAVA=yes
fi

# enable --yes option for some commands in non-interactive mode
YES=
if [ &quot;$INTERACTIVE&quot; == &quot;no&quot; ]; then
  YES=--yes
fi
# --yes by default for opam commands except if we are using the user&#39;s opam switch
if [ &quot;$INTERACTIVE&quot; == &quot;no&quot; ] || [ &quot;$USER_OPAM_SWITCH&quot; == &quot;no&quot; ]; then
    export OPAMYES=true
fi

setup_opam () {
    opam var root 1&gt;/dev/null 2&gt;/dev/null || opam init --reinit --bare --no-setup
    opam_switch_create_if_needed &quot;$INFER_OPAM_SWITCH&quot;
    opam switch set &quot;$INFER_OPAM_SWITCH&quot;
}

install_opam_deps () {
    local locked=
    if [ &quot;$USE_OPAM_LOCK&quot; == yes ]; then
        locked=--locked
    fi
    opam install --deps-only infer &quot;$INFER_ROOT&quot; $locked
}

echo &quot;initializing opam... &quot; &gt;&amp;2
. &quot;$INFER_ROOT&quot;/scripts/opam_utils.sh
if [ &quot;$USER_OPAM_SWITCH&quot; == &quot;no&quot; ]; then
    setup_opam
fi
eval $(SHELL=bash opam env)
echo &gt;&amp;2
echo &quot;installing infer dependencies; this can take up to 30 minutes... &quot; &gt;&amp;2
opam_retry install_opam_deps

if [ &quot;$ONLY_SETUP_OPAM&quot; == &quot;yes&quot; ]; then
  exit 0
fi

echo &quot;preparing build... &quot; &gt;&amp;2
if [ &quot;$BUILD_CLANG&quot; == &quot;no&quot; ]; then
  SKIP_SUBMODULES=true ./autogen.sh &gt; /dev/null
else
  ./autogen.sh &gt; /dev/null
fi

if [ &quot;$BUILD_CLANG&quot; == &quot;no&quot; ]; then
  INFER_CONFIGURE_OPTS+=&quot; --disable-c-analyzers&quot;
fi
if [ &quot;$BUILD_JAVA&quot; == &quot;no&quot; ]; then
  INFER_CONFIGURE_OPTS+=&quot; --disable-java-analyzers&quot;
fi

./configure $INFER_CONFIGURE_OPTS

if [ &quot;$BUILD_CLANG&quot; == &quot;yes&quot; ] &amp;&amp; ! facebook-clang-plugins/clang/setup.sh --only-check-install; then
  echo &quot;&quot;
  echo &quot;  Warning: you are not using a release of Infer. The C and&quot;
  echo &quot;  Objective-C analyses require a custom clang to be compiled&quot;
  echo &quot;  now. This step takes ~30-60 minutes, possibly more.&quot;
  echo &quot;&quot;
  echo &quot;  To speed this along, you are encouraged to use a release of&quot;
  echo &quot;  Infer instead:&quot;
  echo &quot;&quot;
  echo &quot;  http://fbinfer.com/docs/getting-started.html&quot;
  echo &quot;&quot;
  echo &quot;  If you are only interested in analyzing Java programs, simply&quot;
  echo &quot;  run this script with only the \&quot;java\&quot; argument:&quot;
  echo &quot;&quot;
  echo &quot;  $0 java&quot;
  echo &quot;&quot;

  confirm=&quot;n&quot;
  printf &quot;Are you sure you want to compile clang? (y/N) &quot;
  if [ &quot;$INTERACTIVE&quot; == &quot;no&quot; ]; then
    confirm=&quot;y&quot;
    echo &quot;$confirm&quot;
  else
    read confirm
  fi

  if [ &quot;x$confirm&quot; != &quot;xy&quot; ]; then
    exit 0
  fi
fi

make -j &quot;$JOBS&quot; || (
  echo &gt;&amp;2
  echo &#39;  compilation failure; you can try running&#39; &gt;&amp;2
  echo &gt;&amp;2
  echo &#39;    make clean&#39; &gt;&amp;2
  echo &quot;    &#39;$0&#39; $ORIG_ARGS&quot; &gt;&amp;2
  echo &gt;&amp;2
  exit 1)

echo
echo &quot;*** Success! Infer is now built in &#39;$SCRIPT_DIR/infer/bin/&#39;.&quot;
echo &#39;*** Install infer on your system with `make install`.&#39;
echo
echo &#39;*** If you plan to hack on infer, check out CONTRIBUTING.md to setup your dev environment.&#39;
