import 'dart:html';
import 'dart:async';
import 'dart:json' as json;
import 'package:js/js.dart' as js;
import 'package:web_ui/web_ui.dart';


@observable
String userName = '';

List<Map<String, Object>> owed = toObservable(new List());

List<Map<String, Object>> owe = toObservable(new List());

@observable String payFormUrl;
@observable String payKey;
List<Map<String, Object>> payments = toObservable(new List());

Bill newBill = toObservable(new Bill());

var paypalFlow;

void main() {
  // Enable this to use Shadow DOM in the browser.
  //useShadowDom = true;

  setupPaypal();

  HttpRequest.getString('rest/name')
  .then(updateName);

  updateOwe();
  updateOwed();
  updatePayments();
}

void updateOwe() {
  HttpRequest.getString('rest/owe')
  .then((resp) {
    owe.clear();
    owe.addAll(json.parse(resp));
  });
}

void updateOwed() {
  HttpRequest.getString('rest/owed')
  .then((resp) {
    owed.clear();
    owed.addAll(json.parse(resp).map(toObservable));
  });
}

updatePayments() {
  HttpRequest.getString('rest/payments')
  .then((raw) {
    var resp = json.parse(raw);
    payments.clear();
    payments.addAll(resp["Payments"]);
    payKey = resp["PayKey"];
    payFormUrl = resp["PayFormUrl"];
  });
}

void setupPaypal() {
  js.context.paymentFailed = new js.Callback.many(() {
    paypalFlow.closeFlow();
    js.context.jQuery('#pay-failed').show();
  });

  js.context.paymentSucceeded = new js.Callback.many(() {
    updateOwe();
    updatePayments();
    paypalFlow.closeFlow();
  });

  paypalFlow = new js.Proxy(js.context.PAYPAL.apps.DGFlow, js.map({"trigger" : "pay-button"}));
  js.retain(paypalFlow);
}

void updateName(String resp) {
  Map<String, String> name = json.parse(resp);

  if (name['name'] == null) {
    js.context.jQuery("#join").modal(js.map({"keyboard": false}));
    userName = 'New User';
  } else {
    userName = name['name'];
    newBill.initialize();
  }
}

void removeBill(String key) {
  var data = json.stringify({'key': key});
  HttpRequest.request('rest/remove', method: 'POST', sendData: data)
  .then((_) => owed.removeWhere((bill) => bill["Key"] == key));
  //We should handle the error case
}

findUser(String query, reply) {
  var request = new HttpRequest();
  request.open('GET', 'rest/finduser', async: false);
  request.send();

  return js.array(json.parse(request.response));
}

void editNote(Event e, Map<String, Object> bill) {
  Element target = e.currentTarget;

  if (target.children.length < 2) {
    var edit = new TextInputElement();
    edit.value = target.text.trim();
    edit.onBlur.listen((e) {
      var data = json.stringify({'key': bill['Key'],
                                 'note': edit.value,
                                });
      HttpRequest.request('rest/updateNote', method: 'POST', sendData: data)
      .then((_) {
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

class Recipient {
  Bill bill;
  @observable String name;
  @observable String amount;
  @observable bool paid;

  Recipient(this.bill, this.name, this.amount, this.paid);

  String getPaidClass() {
    return this.paid ? "btn-success" : "btn-danger";
  }

  String getPaidText() {
    return this.paid ? "Paid" : "Unpaid";
  }

  void togglePaid() {
    this.paid = !this.paid;
  }

  void updateNamefromTypeahead(elem) {
    this.name = elem;
    bill.adjustRecipients();
  }
  //I would hope there is a better way to do this (like on-load) but I can't find it
  void updateTypeahead(Event e) {
    js.context.jQuery(e.target).typeahead(js.map({"source": new js.Callback.many(findUser),
                                                  "updater": new js.Callback.many(updateNamefromTypeahead),
                                                 }));
  }

  Map<String, Object> toMap() {
    return {"name": name,
            "amount": double.parse(amount),
            "paid": paid
           };
  }
}

class Bill {
  @observable String total = "0.0";
  @observable String notes = "";
  List<Recipient> recipients = toObservable(new List());

  void initialize() {
    total = "0.0";
    notes = "";
    recipients.clear();
    recipients.addAll([new Recipient(this, userName, "0.0", true),
                       new Recipient(this, "", "0.0", false),
                      ]);
  }

  void adjustAmounts() {
    var count = recipients.where((user) => !user.name.isEmpty).length;
    var divided = double.parse(total) / count;
    recipients.forEach((user) { if (!user.name.isEmpty) { user.amount = divided.toString(); }});
  }

  void adjustRecipients() {
    if (recipients[recipients.length - 1].name != "") {
      // Expand
      recipients.add(new Recipient(this, "", "0.0", false));
      adjustAmounts();
    } else if (recipients[recipients.length - 2].name == "") {
      // Contract
      recipients.removeLast();
      adjustAmounts();
    }
  }

  void add() {
    var data = {'note': notes,
                'recipients': recipients.map((user) => user.toMap()).toList(),
               };
    HttpRequest.request('rest/bill', method: 'POST', sendData: json.stringify(data))
    .then((_) {
      updateOwed();
      initialize();
    });
  }
}
