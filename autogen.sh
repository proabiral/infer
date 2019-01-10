#!/bin/bash

# Copyright (c) 2015-present, Facebook, Inc.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

set -e

SCRIPT_DIR=&quot;$( cd &quot;$( dirname &quot;${BASH_SOURCE[0]}&quot; )&quot; &amp;&amp; pwd )&quot;

# make sure we run from the root of the repo
pushd &quot;$SCRIPT_DIR&quot; &gt; /dev/null

# try to pull submodules if we are in a git repo
# might fail if git is not installed (how did you even checkout the
# repo in the first place?)
if test -d &#39;.git&#39; &amp;&amp; [ -z &quot;$SKIP_SUBMODULES&quot; ] ; then
  printf &#39;git repository detected, updating submodule... &#39;
  git submodule update --init &gt; /dev/null
  printf &#39;done\n&#39;
else
  echo &#39;no git repository detected; not updating git submodules&#39;
fi

# We need to record the date that the documentation was last modified to put in our man
# pages. Unfortunately that information is only available reliably from `git`, which we don&#39;t have
# access to from other distributions of the infer source code. Such source distributions should
# distribute the &quot;configure&quot; script too. The idea is to bake this date inside &quot;configure&quot; so that
# it&#39;s available at build time. We do that by generating an m4 macro that hardcodes the date we
# compute in this script for &quot;configure&quot; to find.
MAN_LAST_MODIFIED_M4=m4/__GENERATED__ac_check_infer_man_last_modified.m4
printf &#39;generating %s&#39; &quot;$MAN_LAST_MODIFIED_M4... &quot;
if test -d &#39;.git&#39; ; then
  # date at which the man pages were last modified, to record in the manpages themselves
  MAN_FILES=(
      infer/src/base/CommandLineOption.ml
      infer/src/base/Config.ml
  )
  MAN_DATE=$(git log -n 1 --pretty=format:%cd --date=short -- &quot;${MAN_FILES[@]}&quot;)
  INFER_MAN_LAST_MODIFIED=${INFER_MAN_LAST_MODIFIED:-$MAN_DATE}
else
  echo &#39;no git repository detected; setting last modified date to today&#39;
  # best effort: get today&#39;s date
  INFER_MAN_LAST_MODIFIED=${INFER_MAN_LAST_MODIFIED:-$(date +%Y-%m-%d)}
fi

printf &quot;AC_DEFUN([AC_CHECK_INFER_MAN_LAST_MODIFIED],\n&quot; &gt; &quot;$MAN_LAST_MODIFIED_M4&quot;
printf &quot;[INFER_MAN_LAST_MODIFIED=%s\n&quot; &quot;$INFER_MAN_LAST_MODIFIED&quot; &gt;&gt; &quot;$MAN_LAST_MODIFIED_M4&quot;
printf &quot; AC_SUBST([INFER_MAN_LAST_MODIFIED])\n&quot; &gt;&gt; &quot;$MAN_LAST_MODIFIED_M4&quot;
printf &quot;])\n&quot; &gt;&gt; &quot;$MAN_LAST_MODIFIED_M4&quot;
printf &#39;done\n&#39;

# older versions of `autoreconf` only support including macros via acinclude.m4
ACINCLUDE=&quot;acinclude.m4&quot;
printf &quot;generating $ACINCLUDE...&quot;
cat m4/*.m4 &gt; &quot;$ACINCLUDE&quot;
printf &quot; done\n&quot;

printf &quot;generating ./configure script...&quot;
autoreconf -fi
printf &quot; done\n&quot;

echo &quot;&quot;
echo &quot;you may now run the following commands to build Infer:&quot;
echo &quot;&quot;
echo &quot;  ./configure&quot;
echo &quot;  make&quot;
echo &quot;&quot;
echo &#39;run `./configure --help` for more options&#39;
