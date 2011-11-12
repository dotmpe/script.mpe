#!/bin/bash
origin=$(git remote -v|grep origin|grep fetch|sed -e 's/^origin.\(.*\)..fetch./\1/g')
echo 'Origin:' $origin
[ "$origin" ] || ( echo Need to work from GIT checkout. && exit 2 )

function update-git()
{
    echo Updating...
    [ "$(git status|grep '(added\|modified\|deleted):')" ] && (
        echo "Adding..." \
        && git add --interactive \
        && git commit \
        && return 1
    ) || ( \
        echo "Synchronizing"; \
        [ "$(git status|grep 'On branch test')" ] || (
            git checkout test && update && return 1
        ) \
    ) || \
        return 0
}
function edit()
{
    ( 
        [ ! -f "$1" ] \
        && touch $1 \
        && ( \
            [ "$(git status $1 | grep Untracked)" ] \
            && echo Adding new file: $1 \
            && git add $1
        ) || ( \
            echo "Error creating $1"
        )
    ) || (
        [ "$(git status $1 | grep -i modified)" ] \
        && echo Modified file: $1
    ) || (
        echo git status $1
    )
    #git diff HEAD --no-ext-diff -- $1
}
function commit()
{
    echo git add $1
    echo git commit
    echo git push origin test
}
echo "Calling update"
update-git
dirty=$!
while [ $dirty ];
do 
    echo Dirty
    update-git
    dirty=$!
done
#update $1
#$EDITOR $1
#update $1
#commit $1

