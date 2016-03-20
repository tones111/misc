#!/usr/bin/env bash

# The MIT License (MIT)
#
# Copyright (c) 2016 Paul Sbarra
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Constants ###################################################################

CF_ARGS="-style=file -fallback-style=none"

# Functions ###################################################################

warn() {
   echo $@ >&2
}

error() {
   warn $@
   exit 1
}

command_exists() {
   command -v "$1" &> /dev/null
}

clang-format_diff() {
   local diff=$1; shift

   if [ $diff -ne 0 ]; then
      clang-format $@ | diff - "${@: -1}"
      return ${PIPESTATUS[0]}
   fi
   clang-format $@
}

if git rev-parse --verify HEAD >/dev/null 2>&1; then
	against=HEAD
else
	# Initial commit: diff against an empty tree object
	against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

fmt_err=0
while read -r -a tokens; do
   formatter=
   obj_hash=${tokens[3]}
   file=${tokens[5]}

   if [ ! -f $file ]; then
      continue # skip removed files, submodules
   fi

   ext=${file##*\.}
   case $ext in
      c|cc|cp|cpp|cxx|c++|h|hpp)
         if ! command_exists clang-format; then
            continue
         fi
         formatter=clang-format_diff
         diff_args="1 $CF_ARGS -assume-filename=$file"
         mod_args="0 $CF_ARGS -i"
         ;;

      go)
         formatter=gofmt
         diff_args="-d"
         mod_args="-s -w"
         ;;

      rs)
         formatter=rustfmt
         diff_args="--write-mode diff"
         mod_args="--write-mode overwrite"
         ;;

      *)
         #warn "Unknown file type ($ext): $file"
         continue
         ;;
   esac

   # Verify the command is available
   if [ -z "$formatter" ] || ! `command_exists $formatter`; then
      continue
   fi

   if [ -z "`git diff --name-only -- $file`" ]; then
      if ! $formatter $mod_args $file; then
         warn "syntax error: $file"
         fmt_err=1
      else
         git add $file
      fi
   else # unstaged changes...
      # Note: in order for tools that use a configuration file (clang-format)
      # to find the appropriate configuration the temp file needs to be created in the same
      # directory as the original.  Preserve the file extension to prevent confusing the tool.
      index_file=`dirname $file`/tmp.`basename $file`
      git show $obj_hash > $index_file

      diff=`$formatter $diff_args $index_file 2>/dev/null`
      if [ $? -ne 0 ] || [ -n "$diff" ]; then
         warn "format error, please stage or stash changes: $file"
         fmt_err=1
      fi
      rm $index_file
   fi
done < <(git diff-index --cached --diff-filter=ACMR $against)
exit $fmt_err
