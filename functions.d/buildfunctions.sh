#!/bin/bash
#-------------------------------------------------------------------------------
# buildfunctions.sh - build functions for SBoggit:
#   build_package
#
# Copyright 2013 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.
#
# Redistribution and use of this script, with or without modification, is
# permitted provided that the following conditions are met:
#
# 1. Redistributions of this script must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
#  WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO
#  EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
#  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
#  OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
#  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
#  OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#-------------------------------------------------------------------------------

function build_package
{
  local prg="$1"
  # Returns:
  # 1 - build failed
  # 2 - download failed
  # 3 - checksum failed
  # 4 - installpkg returned nonzero
  # 5 - skipped by hint, or unsupported on this arch
  # 6 - build returned 0 but nothing in $OUTPUT

  local category=$(cd $SB_REPO/*/$prg/..; basename $(pwd))
  echo_lined "$category/$prg"
  hint_skipme $prg && return 5
  rm -f $SB_LOGDIR/$prg.log

  # Load up the .info (and BUILD from the SlackBuild)
  unset PRGNAM VERSION ARCH BUILD TAG DOWNLOAD DOWNLOAD_${SB_ARCH} MD5SUM MD5SUM_${SB_ARCH}
  . $SB_REPO/$category/$prg/$prg.info
  unset BUILD
  buildassign=$(grep '^BUILD=' $SB_REPO/*/$PRGNAM/$PRGNAM.SlackBuild)
  eval $buildassign
  TAG=$SB_TAG
  # At this point we have a full set of environment variables for called functions to use:
  # PRGNAM VERSION SB_ARCH BUILD TAG DOWNLOAD* MD5SUM* etc
  # (use SB_ARCH not ARCH, as SlackBuilds sometimes set ARCH unconditionally)
  if [ "$PRGNAM" != "$prg" ]; then
    echo_yellow "WARNING: PRGNAM in $SB_REPO/$category/$prg/$prg.info is '$PRGNAM', not $prg"
  fi

  # Get the source (including check for unsupported/untested)
  check_src
  case $? in
    0) # already got source, and it's good
       ;;
  1|2) # already got source, but it's bad => get it
       # (note: this includes old source when a package has been upversioned)
       echo "Note: bad checksums in cached source, will download again"
       download_src
       check_src || { save_bad_src; itfailed; return 3; }
       ;;
    3) # not got source => get it
       download_src
       check_src || { save_bad_src; itfailed; return 3; }
       ;;
    4) # unsupported/untested
       return 5
       ;;
  esac

  # Symlink the source into the SlackBuild directory
  ln -sf -t $SB_REPO/$category/$prg/ $SB_SRC/$prg/*

  # Get any hints for the build
  hint_uidgid $prg
  tempmakeflags="$(hint_makeflags $prg)"
  [ -n "$tempmakeflags" ] && echo "Hint: $tempmakeflags"
  options="$(hint_options $prg)"
  [ -n "$options" ] && echo "Hint: options=\"$options\""
  BUILDCMD="env $tempmakeflags $options sh ./$prg.SlackBuild"
  if [ -f $SB_HINTS/$prg.answers ]; then
    echo "Hint: supplying answers from $SB_HINTS/$prg.answers"
    BUILDCMD="cat $SB_HINTS/$prg.answers | $BUILDCMD"
  fi

  # Build it
  echo "SlackBuilding $prg.SlackBuild ..."
  export OUTPUT=$SB_OUTPUT/$prg
  rm -rf $OUTPUT/*
  mkdir -p $OUTPUT
  ( cd $SB_REPO/$category/$prg; eval $BUILDCMD ) >>$SB_LOGDIR/$prg.log 2>&1
  stat=$?
  if [ $stat != 0 ]; then
    echo "ERROR: $prg.SlackBuild failed (status $stat)"
    itfailed
    return 1
  fi

  # Make sure we got *something* :-)
  pkglist=$(ls $OUTPUT/*.t?z 2>/dev/null)
  if [ -z "$pkglist" ]; then
    echo "ERROR: no packages found in $OUTPUT"
    itfailed
    return 6
  fi

  # Install the built packages
  # (this supports multiple output packages because some Slackware SlackBuilds do that)
  for pkgpath in $pkglist; do
    check_package $pkgpath
    install_package $pkgpath || return 4
  done

  itpassed  # \o/
  return 0
}
