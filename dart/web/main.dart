import 'dart:html';
import 'dart:async';
import 'dart:json' as json;
import 'package:js/js.dart' as js;
import 'package:web_ui/web_ui.dart';


@observable
String userName = '';

void main() {
  // Enable this to use Shadow DOM in the browser.
  //useShadowDom = true;

  HttpRequest.getString('rest/name')
  .then(updateName);
}

void updateName(String resp) {
  Map<String, String> name = json.parse(resp);

  if (name['name'] == null) {
    js.context.jQuery("#join").modal(js.map({"keyboard": false}));
    userName = 'New User';
  } else {
    userName = name['name'];
  }
}
