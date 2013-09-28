resp=$(git stash)
dart/build_js.sh
appcfg.py update $(dirname $0)
if [ "$resp" != "No local changes to save" ]; then
    git stash pop
fi
