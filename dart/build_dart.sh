dart --package-root=packages/ packages/web_ui/dwc.dart --out=out --package-root=packages/ --basedir=./ web/main.html
mv out/web/* out/
dart2js --out=out/main.html_bootstrap.dart.js --package-root=packages/ out/main.html_bootstrap.dart
