import 'package:polymer/polymer.dart';
import 'dart:html';
import 'dart:convert';

import "streams.dart";

@CustomTag('x-splitback')
class SplitbackElement extends PolymerElement {
	@observable String userName = '';
	
	List<Map<String, Object>> owed = toObservable(new List());
	List<Map<String, Object>> owe = toObservable(new List());
			
	Streams streams = new Streams();
  
  SplitbackElement.created() : super.created();
  
  @override
  void domReady() {
    streams.billSubmitted.listen((e) {
      print("sill submitted");
   
      updateOwed();
    });
    streams.paymentSucceeded.listen((e) => updateOwe());
	  
	  HttpRequest.getString('/rest/name').then(updateName);
	
	  updateOwe();
	  updateOwed();
	}
	
	void updateOwe([bool paid = false]) {
	  var url = '/rest/owe' + (paid ? '?paid' : '');
	  HttpRequest.getString(url)
	  .then((resp) {
	    owe.clear();
	    owe.addAll(JSON.decode(resp));
	  });
	}
	
	void updateOwed([bool paid = false]) {
	  print("Updating owed");
	  var url = '/rest/owed' + (paid ? '?paid' : '');
	  HttpRequest.getString(url)
	  .then((resp) {
	    owed.clear();
	    owed.addAll(JSON.decode(resp).map(toObservable));
	  });
	}

	void updateName(String resp) {
	  Map<String, String> name = JSON.decode(resp);
    
	  if (name['name'] == null) {
	    //shadowRoot.query("#join")
	    userName = 'New User';
	  } else {
	    userName = name['name'];
	    streams.userNameController.add(userName);
	    print("user: " + userName);
	  }
	}
	
	void removeBill(Event event, var detail, var target) {
    String key = target.attributes['data-key'];
	  
	  var data = JSON.encode({'key': key});
	  HttpRequest.request('rest/remove', method: 'POST', sendData: data)
	  .then((_) => owed.removeWhere((bill) => bill["Key"] == key));
	  //We should handle the error case
	}
	
	void editNote(Event event, var detail, var target) {
	  String key = target.attributes['data-bill-key'];
	  
	  if (target.children.length < 2) {
	    var edit = new TextInputElement();
	    edit.value = target.text.trim();
	    edit.onBlur.listen((e) {
	      var data = JSON.encode({'key': key,
	                              'note': edit.value,
	                              });
	      HttpRequest.request('rest/updateNote', method: 'POST', sendData: data)
	      .then((_) {
	        //This could be much more efficiently done with an index, but we don't have those yet
	        Map<String, Object> bill = owed.firstWhere((b) => b['Key'] == key);
	        bill['Note'] = edit.value;
	        target.children.remove(edit);
	        target.children[0].hidden = false;
	      });
	    });
	    edit.onKeyUp.listen((e) { if (e.keyCode == KeyCode.ENTER) { edit.blur(); }});
	
	    target.children[0].hidden = true;
	    target.children.add(edit);
	    edit.focus();
	  }
	}
	
	void showPaid(Event event, var detail, var target) {
	  String list = target.attributes['data-list'];
    if (list == "owe") {
      updateOwe(true);
    } else {
      updateOwed(true);
    }
	  (target as Element).hidden = true;
	}
}