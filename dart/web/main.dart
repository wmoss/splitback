import 'dart:html';
import 'dart:async';
import 'dart:math';
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

List<String> colors = new List(10);

js.Proxy friendsList = null;
Map<String, String> friends;

StreamSubscription<MouseEvent> amountDragListener = null;

@observable String nameRequired = "";

void main() {
  // Enable this to use Shadow DOM in the browser.
  //useShadowDom = true;

  updateFriends();

  var cat10 = js.context.d3.scale.category10();
  for (int i = 0; i < 10; i++) {
    colors[i] = cat10(i);
  }

  setupPaypal();

  HttpRequest.getString('rest/name')
  .then(updateName);

  updateOwe();
  updateOwed();
  updatePayments();

  query('body').onMouseUp.listen((_) => cancelAmountDragListener());

  FormElement form = query("#join").query("form");
  form.onSubmit.listen((e) {
    if ((form.query("input") as TextInputElement).value.isEmpty) {
      query("#joinNameContainer").classes.add("error");
      nameRequired = "*required*";

      // Stop event
      e.preventDefault();
      e.stopPropagation();
      return false;
    }

    return true;
  });

}

void updateFriends() {
  HttpRequest.getString('rest/finduser')
    .then((raw) {
      friends = json.parse(raw);
      friendsList = js.retain(js.array(friends.keys));
    });
}

void signupNameFocus() {
  query("#joinNameContainer").classes.remove("error");
  nameRequired = "";

}

void updateOwe([bool paid = false]) {
  var url = 'rest/owe' + (paid ? '?paid' : '');
  HttpRequest.getString(url)
  .then((resp) {
    owe.clear();
    owe.addAll(json.parse(resp));
  });
}

void updateOwed([bool paid = false]) {
  var url = 'rest/owed' + (paid ? '?paid' : '');
  HttpRequest.getString(url)
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

void changeName() {
  String name = (query('#name') as TextInputElement).value;
  var data = json.stringify({'name': name});

  HttpRequest.request('rest/updateName', method: 'POST', sendData: data)
  .then((_) => userName = name);
}

void showPaid(f, Event e) {
  f(true);
  (e.target as Element).hidden = true;
}

class Recipient {
  Bill bill;
  @observable String value;
  @observable double amount;
  @observable bool paid;
  int weight = 100;
  bool adjusted = false;

  Recipient(this.bill, this.value, this.amount, this.paid);
  Recipient.empty(this.bill) : value = "", amount = 0.0, paid = false;

  String getPaidClass() {
    return this.paid ? "btn-success" : "btn-danger";
  }

  String getPaidText() {
    return this.paid ? "Paid" : "Unpaid";
  }

  void togglePaid() {
    this.paid = !this.paid;
  }

  void updateValuefromTypeahead(elem) {
    this.value = elem;
    bill.maybeExpandRecipients();
  }
  //I would hope there is a better way to do this (like on-load) but I can't find it
  void updateTypeahead(Event e) {
    js.context.jQuery(e.target).typeahead(js.map({"source": friendsList,
                                                  "updater": new js.Callback.many(updateValuefromTypeahead),
                                                 }));
  }

  Map<String, Object> toMap() {
    return {"value": value,
            "key": friends[value],
            "amount": amount,
            "paid": paid
           };
  }
}

class Bill {
  @observable String total = "0.0";
  @observable String notes = "";
  List<Recipient> recipients = toObservable(new List());

  Stream onUpdate, onAdjust;
  StreamController onUpdateController, onAdjustController;
  Bill() {
    onUpdateController = new StreamController();
    onUpdate = onUpdateController.stream;
    onAdjustController = new StreamController();
    onAdjust = onAdjustController.stream;
  }

  void initialize() {
    total = "0.0";
    notes = "";
    recipients.clear();
    recipients.addAll([new Recipient(this, userName, 0.0, true),
                       new Recipient.empty(this),
                      ]);

    recalculateWeights();
  }

  void adjustAmounts() {
    validRecipients().forEach((r) => r.amount = double.parse(total) * r.weight / 100);
  }

  void maybeAdjustRecipients() {
    maybeExpandRecipients();
    maybeContractRecipients();
  }

  void maybeExpandRecipients() {
    if (recipients[recipients.length - 1].value != "") {
      // Expand
      recipients.add(new Recipient.empty(this));
      recalculateWeights();
      adjustAmounts();
      new Timer(new Duration(milliseconds: 5),
                () => queryAll(".recipient").last.focus());
    }
  }

  void maybeContractRecipients() {
    if (recipients[recipients.length - 2].value == "") {
      // Contract
      recipients.removeLast();
      recalculateWeights();
      adjustAmounts();
    }
  }

  void recalculateWeights() {
    List<Recipient> recipients = validRecipients().toList();
    List<Recipient> movable = recipients.where((r) => !r.adjusted).toList();
    if (movable.isEmpty) {
      recipients.last.adjusted = false;
      recalculateWeights();
      return;
    }

    int remaining = 100 - recipients.where((r) => r.adjusted).fold(0, (p, e) => p + e.weight);
    int divided = (remaining / movable.length).round();
    for (int i = 0; i < movable.length - 1; i++) {
      movable[i].weight = divided;
      remaining -= divided;
    }
    movable.last.weight = remaining;

    onUpdateController.add(null);
  }

  void add() {
    query('#bill-error').hidden = true;
    var data = {'note': notes,
                'recipients': recipients.map((user) => user.toMap()).toList(),
               };
    HttpRequest.request('rest/bill', method: 'POST', sendData: json.stringify(data))
    .then((_) {
      updateOwed();
      initialize();
    })
    .catchError((req) {
      Map<String, String> err = json.parse(req.currentTarget.responseText);
      if (err['error'] == 'unknown recipient') {
        query('#bill-error').hidden = false;
      }
    }, test: (req) => req.currentTarget.status == 400);
  }

  validRecipients() => recipients.where((r) => r.value != "");
}

void cancelAmountDragListener() {
  if (amountDragListener != null) {
    amountDragListener.cancel();
    amountDragListener = null;
  }
}

void dragAmountStart(int index, MouseEvent e) {
  if (e.which == 1) {
    cancelAmountDragListener();
    amountDragListener = query('body').onMouseMove.listen((e) {
      newBill.onAdjustController.add([index, e.movementX]);
    });
  }
}
