import 'dart:io';
import 'package:web_ui/component_build.dart';

// Ref: http://www.dartlang.org/articles/dart-web-components/tools.html
main() {
  var args = new Options().arguments.toList();
  args.addAll(['--', '--package-root', 'packages/', '--basedir', './']);
  build(args, ['web/main.html']);
}
