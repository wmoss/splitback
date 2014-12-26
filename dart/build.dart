import 'package:polymer/builder.dart';

/*export 'package:polymer/default_build.dart';
*/

void main() {
  build(entryPoints: ['web/main.html'], options: parseOptions(['--deploy', '--no-js']));
}
