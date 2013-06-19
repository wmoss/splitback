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

js.Proxy friends = null;

StreamSubscription<MouseEvent> amountDragListener = null;

void main() {
  // Enable this to use Shadow DOM in the browser.
  //useShadowDom = true;

  HttpRequest.getString('rest/finduser')
    .then((resp) => friends = js.retain(js.array(json.parse(resp))));

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
  setupPieChart();

  query('body').onMouseUp.listen((_) => cancelAmountDragListener());
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

class Recipient {
  Bill bill;
  @observable String name;
  @observable double amount;
  @observable bool paid;
  int weight = 100;
  bool adjusted = false;

  Recipient(this.bill, this.name, this.amount, this.paid);
  Recipient.empty(this.bill) : name = "", amount = 0.0, paid = false;

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
    bill.maybeExpandRecipients();
  }
  //I would hope there is a better way to do this (like on-load) but I can't find it
  void updateTypeahead(Event e) {
    js.context.jQuery(e.target).typeahead(js.map({"source": friends,
                                                  "updater": new js.Callback.many(updateNamefromTypeahead),
                                                 }));
  }

  Map<String, Object> toMap() {
    return {"name": name,
            "amount": amount,
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
    recipients.addAll([new Recipient(this, userName, 0.0, true),
                       new Recipient.empty(this),
                      ]);

    recalculateWeights();
  }

  void adjustAmounts() {
    validRecipients().forEach((r) => r.amount = double.parse(total) * r.weight / 100);
  }

  void maybeExpandRecipients() {
    if (recipients[recipients.length - 1].name != "") {
      // Expand
      recipients.add(new Recipient.empty(this));
      recalculateWeights();
      adjustAmounts();
      new Timer(new Duration(milliseconds: 5),
                () => queryAll(".recipient").last.focus());
    }
  }

  void maybeContractRecipients() {
    if (recipients[recipients.length - 2].name == "") {
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
    updatePieChart();
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

  validRecipients() => recipients.where((r) => r.name != "");
}

int width = 250, height = 250, radius = 125;
js.Proxy svg, chart, labels, d3 = js.retain(js.context.d3);
void setupPieChart() {
  js.scoped(() {
    svg = d3.select("#split-chart").append("svg")
        .attr("width", width)
        .attr("height", height)
        .append("g")
        .attr("transform", "translate(" + (width / 2).toString() + "," + (height / 2).toString() + ")");
    chart = js.retain(svg.append("g"));
    labels = js.retain(svg.append("g"));

    js.retain(svg);
  });
}

void updatePieChart() {
  js.scoped(() {
    List<js.Proxy> data = new List();
    List<Recipient> valid = newBill.validRecipients().toList();
    for (int i = 0; i < valid.length; i++) {
      data.add(js.map({'i': i, 'w': valid[i].weight}));
    }
    js.FunctionProxy pie = d3.layout.pie()
      .sort(new js.Callback.many((r, i) => r['i']))
      .value(new js.Callback.many((r, i) => r['w']));

    js.FunctionProxy color = d3.scale.category10();

    js.Proxy arc = d3.svg.arc()
      .innerRadius(0)
      .outerRadius(radius - 20);

    js.Proxy drag = d3.behavior.drag()
      .on("drag", new js.Callback.many(dragPieChart));

    js.Proxy arcs = chart.selectAll("path")
      .data(pie(js.array(data)));
    arcs.enter().append("path");
    arcs['call'](drag); //call is a reserved word in dart, so we need to call the method this way

    arcs.exit().remove();

    chart.selectAll("path")
      .data(pie(js.array(data)))
      .attr("d", arc)
      .attr("fill", new js.Callback.many((d, i, c) => color(i)));

    js.Proxy texts = labels.selectAll("text")
        .data(pie(js.array(data)));

    js.Callback textTransform;
    if (data.length > 1) {
      textTransform = new js.Callback.many((d, i, c) => "translate(" + arc.centroid(d).toString() + ")");
    } else {
      textTransform = new js.Callback.many((d, i, c) => "translate(-18,0)");
    }

    texts.enter()
      .append("text")
      .attr("transform", textTransform)
      .attr("dy", ".35em")
      .style("fill", "white")
      .text(new js.Callback.many((d, i, c) => d.data['w'].toStringAsFixed(0) + '%'));
    texts.exit().remove();

    labels.selectAll("text")
      .data(pie(js.array(data)))
      .text(new js.Callback.many((d, i, c) => d.data['w'].toStringAsFixed(0) + '%'))
      .attr("transform", textTransform);
  });
}

void dragPieChart(d, i, c) {
  adjustPieChart(d.data['i'], d3.event.dx);
}

void adjustPieChart(int index, int dx) {
  List<Recipient> recipients = newBill.validRecipients().toList();
  Recipient active = newBill.recipients[index];
  if (recipients.where((r) => !r.adjusted && r != active).length == 0) {
    return;
  }

  active.adjusted = true;

  List<Recipient> movable = recipients.where((r) => !r.adjusted).toList();

  int delta = dx * movable.length;
  int value = active.weight + delta;
  int fixedAmount = recipients.where((r) => r.adjusted).fold(0, (p, e) => p + e.weight);
  if (value < 1 || value > 100 - (fixedAmount  - active.weight) - movable.length) {
    return;
  }

  active.weight += delta;
  movable.forEach((r) => r.weight -= (delta / movable.length).toInt());

  updatePieChart();
  newBill.adjustAmounts();
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
      adjustPieChart(index, e.movementX);
    });
  }
}
