import 'package:polymer/polymer.dart';
import 'dart:html';

import '../dart/web/streams.dart';


@CustomTag('auto-complete')
class AutoCompleteElement extends PolymerElement { 
  @published ObservableList<String> haystack;
  @published String search;
  
  final ObservableList<String> results = new ObservableList();
  bool skipSearch = false;
  int keyboardSelect = -1;
  int left = 0, top = 0, width = 200;
  Streams streams = new Streams();
  
  AutoCompleteElement.created() : super.created();
  
  @override
  void domReady() {
    TextInputElement _underlying = this.querySelector('input');
    
    _underlying.onKeyUp.listen((e) => _keyup(e));
    //_underlying.onBlur.listen((e) => streams.recipientEnteredController.add(search));
    
    final docElem = document.documentElement;
    final box = _underlying.getBoundingClientRect();
    left = box.left + window.pageXOffset - docElem.clientLeft;
    top = box.top + window.pageYOffset - docElem.clientTop + _underlying.clientHeight;
    width = _underlying.clientWidth;
  }
  
  void updateSearch(String val) {
    search = val;
    print("Adding new event");
    streams.recipientEnteredController.add(search);
  }
  
  void select(Event e, var detail, Node target) {
    updateSearch(target.text);
    _reset();
    skipSearch = true;
  }
  
  _performSearch() {
    if (skipSearch) {
      skipSearch = false;
      return;
    }
    results.clear();
    if (search.trim().isEmpty) return;
    String lower = search.toLowerCase();
    results.addAll(haystack.where((String term) {
      return term.toLowerCase().startsWith(lower);
    }));
  }
  
  _keyup(KeyboardEvent e) {
    switch (e.keyCode) {
      case KeyCode.ESC:
        _clear();
        break;
      case KeyCode.UP:
        _moveUp();
        break;
      case KeyCode.DOWN:
        _moveDown();
        break;
      case KeyCode.ENTER:
        _select();
        break;
      default:
        _performSearch();
    }
  }
  
  _moveDown() {
    List<Element> lis = shadowRoot.querySelectorAll('ul li');
    if (keyboardSelect >= 0) lis[keyboardSelect].classes.remove('selecting');
    keyboardSelect = ++keyboardSelect == lis.length ? 0 : keyboardSelect;
    lis[keyboardSelect].classes.add('selecting');
  }
  
  _moveUp() {
    List<Element> lis = shadowRoot.querySelectorAll('ul li');
    if (keyboardSelect >= 0) lis[keyboardSelect].classes.remove('selecting');
    if (keyboardSelect == -1) keyboardSelect = lis.length;
    keyboardSelect = --keyboardSelect == -1 ? lis.length-1 : keyboardSelect;
    lis[keyboardSelect].classes.add('selecting');
  }
  
  _clear() {
    _reset();
    search = '';
    skipSearch = true;
  }
  
  _select() {
    List<Element> lis = shadowRoot.querySelectorAll('ul li');
    if (lis.isNotEmpty) {
      updateSearch(lis[keyboardSelect].text);
      skipSearch = true;
      _reset();
    }
  }
  
  _reset() {
    keyboardSelect = -1;
    results.clear();
  }
}