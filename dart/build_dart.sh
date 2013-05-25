dart --package-root=packages/ packages/web_ui/dwc.dart --out=web/out --package-root=packages/ --basedir=./ web/main.html
dart2js --out=web/out/web/main.html_bootstrap.dart.js --package-root=packages/ web/out/web/main.html_bootstrap.dart
