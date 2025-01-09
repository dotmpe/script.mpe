alias fname='find . -name '
alias finame='find . -iname '
alias fipath='find . -ipath '
alias fnipath='find . -ipath '

# [2017-04-16] find executables on OSX with BSD/Darwins 2011 find w/o -executable flag support
alias find-exec="find . -type f -exec test -x {} \; -a -print"

alias find-symlinks='find . -xtype l'

# FIXME:
alias find-symlink-targets='find . -xtype l -printf "%p %l\\n" '
#alias find-symlink-fnmatch=''

# See also e.g. user-tools backgrounds
alias find-images='find ~/Pictures -iname "*.jpg" -o -iname "*.gif" -o -iname "*.png"'


# Naive impl. but also lists directories
alias find-largest='ls -S | head'

# Using find
alias find-largest-file='find $PWD -type f -printf "%s %p\\n" | sort -rn | head'
alias find-oldest-file='find $PWD -type f -printf "%T+ %p\\n" | sort -rn | head'
alias find-newest-file='find $PWD -type f -printf "%T+ %p\\n" | sort -n | tail'

#
