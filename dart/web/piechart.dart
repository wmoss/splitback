import 'package:web_ui/web_ui.dart';
import 'package:js/js.dart' as js;
import 'dart:html';

class Chartable {
  int weight;
  bool adjusted;
}

class PieChart extends WebComponent {
  @observable var bill;

  int width = 250, height = 250, radius = 125;
  js.Proxy svg, chart, labels, d3 = js.retain(js.context.d3);

  inserted() {
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

    bill.onUpdate.listen((String m) {
      updatePieChart();
    });

    bill.onAdjust.listen((List<Object> e) {
      adjustPieChart(e[0], e[1]);
    });
  }

  void updatePieChart() {
    js.scoped(() {
      List<js.Proxy> data = new List();
      List<Chartable> valid = bill.validRecipients().toList();
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
    movable.forEach((r) => r.weight -= (delta / movable.length).toInt());

    updatePieChart();
    bill.adjustAmounts();
  }
}