import 'package:polymer/polymer.dart';
import 'package:uuid/uuid.dart';
import 'dart:html' show DivElement;


@CustomTag('x-recipient')
class Recipient extends Observable {
  @observable String value = "";
  @observable double amount = 0.0;
  @observable bool paid = false;
  @observable Map<String, String> keys;
  String id = new Uuid().v4();

  Recipient.named(this.value, this.amount, this.paid, this.keys) {}
  Recipient.empty(this.keys) : value = "", amount = 0.0, paid = false {}
  
  String get paidClass {
    return this.paid ? "btn-success" : "btn-danger";
  }

  String get paidText {
    return this.paid ? "Paid" : "Unpaid";
  }

  void togglePaid() {
    this.notifyPropertyChange(const Symbol('paidClass'), this.paid, !this.paid);
    this.notifyPropertyChange(const Symbol('paidText'), this.paid, !this.paid);
    this.paid = !this.paid;
  }

  Map<String, Object> toMap() {
    return {"value": value,
            "key": keys[value],
            "amount": amount,
            "paid": paid
           };
  }
}