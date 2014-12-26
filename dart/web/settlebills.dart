import 'package:polymer/polymer.dart';
import 'dart:js';
import 'dart:convert';
import 'dart:html';

import 'streams.dart';


@CustomTag('x-settlebills')
class SettleBills extends PolymerElement {
  bool get applyAuthorStyles => true;

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
  }
  
  void updatePayments() {
    HttpRequest.getString('/rest/payments')
    .then((raw) {
      var resp = JSON.decode(raw);
      payments.clear();
      payments.addAll(resp["Payments"]);
      payKey = resp["PayKey"];
      payFormUrl = resp["PayFormUrl"];
      /* TODO: Replace with bindProperty when that works better */
      //notifyProperty(this, const Symbol('paymentsEmpty'));
      
      var el = this.shadowRoot.querySelector("#pay-button");
      el.attributes.remove("disabled");
      el.onClick.listen((e) => paypalFlow.callMethod('startFlow', [payFormUrl + '?expType=light&payKey=' + payKey]));
    });
  }

  void hideAlert(Event event, var detail, var target) {
    target.parent.hidden = true;
  }
  
}