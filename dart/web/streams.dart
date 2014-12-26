library utilities;

import 'dart:async';


class Streams {
  Stream userName, recipientEntered, billSubmitted, paymentSucceeded;
  StreamController userNameController, recipientEnteredController, billSubmittedController, paymentSucceededController;
  
  static final Streams _singleton = new Streams._internal();

  factory Streams() {
    return _singleton;
  }

  Streams._internal() {
    userNameController = new StreamController.broadcast();
    userName = userNameController.stream;
    billSubmittedController = new StreamController.broadcast();
    billSubmitted = billSubmittedController.stream;
    paymentSucceededController = new StreamController.broadcast();
    paymentSucceeded = paymentSucceededController.stream;
  } 
}