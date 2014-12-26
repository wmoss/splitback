import 'package:polymer/polymer.dart';
import 'dart:html';
import 'dart:convert';
import 'dart:async';

@CustomTag('x-myinfo')
class MyInfo extends PolymerElement {
  static const delay = const Duration(seconds: 1);
  
  @published String username;
  Timer postTimer = null;
  Timer successTimer = null;
  var input = null;
  
  MyInfo.created() : super.created();
  
  @override
  void domReady() {
    this.shadowRoot.querySelector("#name").onKeyUp.listen((KeyboardEvent e) {
      if(postTimer != null) { postTimer.cancel(); }
      postTimer = new Timer(delay, updateName);
    });
  }
  
  void updateName() {
    print('Updating name');
    HttpRequest.request('/rest/updateName', method: 'POST', sendData: JSON.encode({'name': username}))
    .then((e) {
      toggleSuccess();
      if(successTimer != null) { successTimer.cancel(); }
      successTimer = new Timer(delay, toggleSuccess);
    });
  }
  
  void toggleSuccess() {
    var success = this.shadowRoot.querySelector("#success");
    success.style.display = (success.style.display == '' ? 'none' : '');
  }
}