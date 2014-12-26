import 'package:polymer/polymer.dart';
import 'dart:html';
import 'dart:convert';
import 'dart:async';

@CustomTag('x-myinfo')
class MyInfo extends PolymerElement {  
  @published String username;
  Timer postTimer = null;
  Timer successTimer = null;
  var input = null;
  
  MyInfo.created() : super.created();
  
  @override
  void domReady() {
    this.shadowRoot.querySelector("#name").onKeyUp.listen((KeyboardEvent e) {
      if(postTimer != null) { postTimer.cancel(); }
      postTimer = new Timer(new Duration(seconds: 1), updateName);
    });
  }
  
  void updateName() {
    HttpRequest.request('/rest/updateName', method: 'POST', sendData: JSON.encode({'name': username}))
    .then((e) {
      toggleSuccess();
      if(successTimer != null) { successTimer.cancel(); }
      successTimer = new Timer(new Duration(seconds: 3), toggleSuccess);
    });
  }
  
  void toggleSuccess() {
    this.shadowRoot.querySelector("form").classes.toggle('has-success');
    this.shadowRoot.querySelector(".glyphicon-ok").classes.toggle('hidden');
  }
}