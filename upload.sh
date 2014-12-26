set -e

if [ -n "$(git diff)" ]; then
    while true; do
        read -p "Unstaged changes, continue? [yN] " yn
        case $yn in
            [Yy]* ) break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
fi

cd dart && pub build
cd ..
appcfg.py -e wbmoss@gmail.com update $(dirname $0)
