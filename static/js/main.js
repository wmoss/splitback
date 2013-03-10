$(document).ready(function() {
    $("input").bind("input", AdjustAmounts);

    $('#User1').typeahead({source: findUser});
    $('#User2').typeahead({source: findUser});
});

function AdjustAmounts() {
    var amounts = $(".amount")
    var used = amounts.filter(function(index) {
        return $("#User" + index).val() != ""
    });
    var unused = amounts.filter(function(index) {
        return $("#User" + index).val() == ""
    });

    var divided = $("#amount").val() / used.length;
    used.each(function() { $(this).val(divided.toFixed(2)); });
    unused.val("");
}

function findUser(query, reply) {
    $.get(
        "/finduser",
        "query=" + query,
        function(data) { reply(data); },
        "json"
    );
}
