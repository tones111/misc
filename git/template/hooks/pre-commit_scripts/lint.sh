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

if git rev-parse --verify HEAD >/dev/null 2>&1; then
	against=HEAD
else
	# Initial commit: diff against an empty tree object
	against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

lint_err=0
while read -r -a tokens; do
   linter=
   obj_hash=${tokens[3]}
   file=${tokens[5]}

   if [ ! -f $file ]; then
      continue # skip removed files, submodules
   fi

   ext=${file##*\.}
   case $ext in
      c|cc|cp|cpp|cxx|c++|h|hpp)
         linter=cppcheck
         args="--error-exitcode=1"
         ;;

      go)
         linter=go
         args="vet"
         ;;

      *)
         #warn "Unknown file type ($ext): $file"
         continue
         ;;
   esac

   # Verify the command is available
   if [ -z "$linter" ] || ! `command_exists $linter`; then
      continue
   fi

   if [ -z "`git diff --name-only -- $file`" ]; then
      if ! $linter $args $file; then
         lint_err=1
      fi
   else # unstaged changes...
      # Note: lint tools output the filename if an error is found.
      # Since we don't want to upset the working tree, pick a similar name.
      index_file=`dirname $file`/tmp.`basename $file`
      git show $obj_hash > $index_file
      if ! $linter $args $index_file; then
         lint_err=1
      fi
      rm $index_file
   fi
done < <(git diff-index --cached --diff-filter=ACMR $against)

if [ "$lint_err" -ne "0" ]; then
   error "Please fix errors before commiting (ignore with -n)"
fi
exit $lint_err
