resp=$(git stash)
dart/build_js.sh
/home/wmoss/contrib/google_appengine/appcfg.py update .
if [ "$resp" != "No local changes to save" ]; then
    git stash pop
fi
