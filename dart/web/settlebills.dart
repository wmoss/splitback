import 'package:polymer/polymer.dart';
import 'dart:js';
import 'dart:convert';
import 'dart:html';

import 'streams.dart';


@CustomTag('x-settlebills')
class SettleBills extends PolymerElement {
  JsObject paypalFlow;
  @observable String payFormUrl;
  @observable String payKey;
  
  Streams events = new Streams();
  
  ObservableList<Map<String, Object>> payments = new ObservableList();
    
  SettleBills.created() : super.created();
  
  @override
  void domReady() {
    context['paymentFailed'] = () {
      paypalFlow.callMethod('closeFlow');
      this.shadowRoot.querySelector('#pay-failed').hidden = false;
    };
    
    context['paymentSucceeded'] = () {
      events.paymentSucceededController.add(null);
      updatePayments();
      paypalFlow.callMethod('closeFlow');
    };
    
    paypalFlow = new JsObject(context['PAYPAL']['apps']['DGFlow']);
    
    updatePayments();
    updatePaypalKey();
    
    this.shadowRoot.querySelector("#pay-square-cash").onClick.listen((e) {
      window.location.assign("/rest/getOAuthToken");
    });
  }
  
  String get totalOwed => payments.fold(0, (last, payment) => last + payment["Amount"]);
  
  void updatePayments() {
    HttpRequest.getString('/rest/payments')
    .then((raw) {
      var previousOwed = totalOwed;
      var resp = JSON.decode(raw);
      payments.clear();
      payments.addAll(resp);
      this.notifyPropertyChange(const Symbol('totalOwed'), previousOwed, totalOwed);
    });
  }

  void updatePaypalKey() {
    HttpRequest.getString('/rest/paypalPayKey')
     .then((raw) {
       var resp = JSON.decode(raw);
       payKey = resp["PayKey"];
       payFormUrl = resp["PayFormUrl"];       
       var el = this.shadowRoot.querySelector("#pay-button");
       el.attributes.remove("disabled");
       el.onClick.listen((e) => paypalFlow.callMethod('startFlow', [payFormUrl + '?expType=light&payKey=' + payKey]));
     });    
  }
  
  void hideAlert(Event event, var detail, var target) {
    target.parent.hidden = true;
  }
  
}