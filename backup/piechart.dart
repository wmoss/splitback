import 'package:polymer/polymer.dart';
import 'dart:js' as js;

class Chartable {
  int weight;
  bool adjusted;
}

@CustomTag('x-piechart')
class PieChart extends PolymerElement {
  @observable var bill;

  int width = 250, height = 250, radius = 125;
  js.JsObject svg, chart, labels, d3 = js.context['d3'];

  PieChart.created() : super.created();
  
  @override
  void enteredView() {
    svg = d3.callMethod('select', ["#split-chart"]).append("svg")
        .attr("width", width)
        .attr("height", height)
        .append("g")
        .attr("transform", "translate(" + (width / 2).toString() + "," + (height / 2).toString() + ")");
    chart = svg.callMethod('append', ["g"]);
    labels = svg.callMethod('append', ["g"]);

    bill.onUpdate.listen((String m) {
      updatePieChart();
    });

    bill.onAdjust.listen((List<Object> e) {
      adjustPieChart(e[0], e[1]);
    });
  }

  void updatePieChart() {
    List<js.JsObject> data = new List();
    List<Chartable> valid = bill.validRecipients().toList();
    for (int i = 0; i < valid.length; i++) {
      data.add(new js.JsObject.jsify({'i': i, 'w': valid[i].weight}));
    }
    js.JsFunction pie = d3['layout'].callMethod('pie')
      .sort((r, i) => r['i'])
      .value((r, i) => r['w']);

    js.JsFunction color = d3['scale'].callMethod('category10');

    js.JsFunction arc = d3['svg'].callMethod('arc')
      .innerRadius(0)
      .outerRadius(radius - 20);

    js.JsFunction drag = d3.behavior.drag()
      .on("drag", dragPieChart);

    js.JsFunction arcs = chart['selectAll']("path")
      .data(pie.apply([new js.JsObject.jsify(data)]));
    arcs.callMethod('enter').append("path");
    arcs.callMethod('call', [drag]); //call is a reserved word in dart, so we need to call the method this way

    arcs.callMethod('exit').remove();

    chart.selectAll("path")
      .data(pie(new js.JsObject.jsify(data)))
      .attr("d", arc)
      .attr("fill", (d, i, c) => color(i));

    js.Proxy texts = labels.selectAll("text")
        .data(pie(new js.JsObject.jsify(data)));

    var textTransform;
    if (data.length > 1) {
      textTransform = (d, i, c) => "translate(" + arc["centroid"](d).toString() + ")";
    } else {
      textTransform = (d, i, c) => "translate(-18,0)";
    }

    texts.enter()
      .append("text")
      .attr("transform", textTransform)
      .attr("dy", ".35em")
      .style("fill", "white")
      .text((d, i, c) => d.data['w'].toStringAsFixed(0) + '%');
    texts.exit().remove();

    labels.selectAll("text")
      .data(pie(new js.JsObject.jsify(data)))
      .text((d, i, c) => d.data['w'].toStringAsFixed(0) + '%')
      .attr("transform", textTransform);
  }

  void dragPieChart(d, i, c) {
    adjustPieChart(d.data['i'], d3['event']['dx']);
  }

  void adjustPieChart(int index, int dx) {
    List<Chartable> recipients = bill.validRecipients().toList();
    Chartable active = bill.recipients[index];

    if (recipients.length == 2 && !active.adjusted) {
      // If we only have two recipients, let the user drag either one
      recipients.firstWhere((r) => r != active).adjusted = false;
    }

    if (recipients.where((r) => !r.adjusted && r != active).length == 0) {
      return;
    }

    active.adjusted = true;

    List<Chartable> movable = recipients.where((r) => !r.adjusted).toList();

    int delta = dx * movable.length;
    int value = active.weight + delta;
    int fixedAmount = recipients.where((r) => r.adjusted).fold(0, (p, e) => p + e.weight);
    if (value < 1 || value > 100 - (fixedAmount  - active.weight) - movable.length) {
      return;
    }

    active.weight += delta;
    movable.forEach((r) => r.weight -= delta ~/ movable.length);

    updatePieChart();
    bill.adjustAmounts();
  }
}