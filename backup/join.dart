import 'package:polymer/polymer.dart';
import 'dart:html';


@CustomTag('x-join')
class SettleBills extends PolymerElement {
  bool get applyAuthorStyles => true;

  @observable bool nameMissing = false;

  SettleBills.created() : super.created(); 
  
  @override
  void domReady() {
    FormElement form = this.shadowRoot.querySelector("#join").querySelector("form");
    form.onSubmit.listen((e) {
      if ((form.querySelector("input") as TextInputElement).value.isEmpty) {
        nameMissing = true;
        //this.shadowRoot.query("#joinNameContainer").classes.add("error");
        //nameRequired = "*required*";
        
        // Stop event
        e.preventDefault();
        e.stopPropagation();
        return false;
      }
      
      return true;
    });
    
    void signupNameFocus(event, detail, target) {
      nameMissing = false;
      //this.shadowRoot.query("#joinNameContainer").classes.remove("error");
      //nameRequired = "";
    }
  }
}