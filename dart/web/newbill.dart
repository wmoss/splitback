import 'package:polymer/polymer.dart';
import 'dart:async';
import 'dart:html';
import 'dart:convert';

import "recipient.dart";
import "streams.dart";


@CustomTag('x-newbill')
class NewBill extends PolymerElement {
  @published String username = "";
  @observable String total = "";
  @observable String notes = "";
  ObservableList<Recipient> recipients = new ObservableList();
  ObservableMap<String, String> friends = new ObservableMap();
    
  Streams events = new Streams();
  
  usernameChanged(_) => resetRecipients();
  
  NewBill.created() : super.created();
  
  @override 
  void domReady() {
    updateFriends();
  }

  void reset() {
    total = "";
    notes = "";
    resetRecipients();
  }
  
  void resetRecipients() {
    recipients.clear();
    recipients.addAll([new Recipient.named(username, 0.0, true, friends),
                       new Recipient.empty(friends)]);
  }

  void totalUpdated(event, detail, target) => adjustAmounts();
  
  void adjustAmounts() {
    if (total.isNotEmpty) {
      var valid = validRecipients();
      var remaining = double.parse(total);
      int divider = valid.length;
      valid.forEach((r) {
        r.amount = (100 * remaining / divider).round() / 100.0;
        remaining -= r.amount;
        divider--;
      });
    }
  }

  void updateRecipients() {
    if (recipients[recipients.length - 1].value != "") {
      recipients.add(new Recipient.empty(friends));
    }
    
    recipients.removeWhere((e) => e.value.isEmpty && e != recipients.last);
    
    adjustAmounts();
  }
  
  void maybeTest(Event event, var detail, var target) => updateRecipients();

  void togglePaid(Event event, var detail, var target) {
    Recipient recipient = recipients.firstWhere((r) => r.id == target.getAttribute("data-user-id"));
    recipient.togglePaid();
  }
  
  void add(Event event, var detail, var target) {
    shadowRoot.querySelector('#bill-error').hidden = true;
    var data = {'note': notes,
                'recipients': recipients.map((user) => user.toMap()).toList(),
               };
    HttpRequest.request('/rest/bill', method: 'POST', sendData: JSON.encode(data))
    .then((_) {
      new Timer(new Duration(milliseconds: 500), () {
        events.billSubmittedController.add(null);
        print("SubmitteD");
      });
      reset();
    })
    .catchError((ProgressEvent req) {
      Map<String, String> err = JSON.decode((req.target as HttpRequest).responseText);
      var error = shadowRoot.querySelector('#bill-error');
      error.querySelector("p").text = err['error'];
      error.hidden = false;
    }, test: (req) => req.currentTarget.status == 400);
  }

  validRecipients() => recipients.where((r) => r.value != "");

  void updateFriends() {
    HttpRequest.getString('/rest/finduser')
      .then((raw) {
      friends.clear();
      friends.addAll(JSON.decode(raw));
    });
  }
  
  void hideAlert(Event event, var detail, var target) {
    target.parent.hidden = true;
  }
}