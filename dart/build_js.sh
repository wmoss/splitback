ROOT=$(dirname $0)
dart --package-root=$ROOT/packages/ $ROOT/packages/web_ui/dwc.dart --out=$ROOT/web/out --package-root=$ROOT/packages/ --basedir=$ROOT/./ $ROOT/web/main.html
dart2js --out=$ROOT/web/out/web/main.html_bootstrap.dart.js --package-root=$ROOT/packages/ $ROOT/web/out/web/main.html_bootstrap.dart
