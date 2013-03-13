var app = angular.module('splitback', ['$strap.directives']);

app.controller("NewBillCtrl", function($scope) {
    $scope.recipients = [
        {"name": name, "amount": 0, "paid": true},
        {"name": "", "amount": 0, "paid": false}
    ];

    $scope.adjust = function() {
        var count = 0;
        angular.forEach($scope.recipients,
                        function(value) {
                            if (value.name != "") { count++; }
                        });

        var amount = $scope.amount == "" ? 0 : $scope.amount;
        var divided = amount / count;
        angular.forEach($scope.recipients,
                        function(value) {
                            if (value.name == "") {
                                value.amount = 0
                            } else {
                                value.amount = divided;
                            }
                        });
    };

    $scope.findUser = function(query, reply) {
        $.get(
            "/finduser",
            "",
            function(data) { reply(data); },
            "json"
        );
    };

    $scope.checkMore = function() {
        if ($scope.recipients[$scope.recipients.length - 1].name != "") {
            // Expand
            $scope.recipients[$scope.recipients.length] = {"name": "", "amount": 0, "paid": false};
            $scope.adjust()
        } else if ($scope.recipients[$scope.recipients.length - 2].name == "") {
            // Contract
            $scope.recipients.splice($scope.recipients.length - 1, $scope.recipients.length);
            $scope.adjust()
        }
    };

    $scope.addBill = function() {
        $.ajax({
            type: "POST",
            url: "/bill",
            data: JSON.stringify($scope.recipients),

            success: function(data, status) {
                $("#owed").html(data);
            }
        });
    };

    $scope.togglePaid = function(user) {
        user.paid = !user.paid;
    };

    $scope.getButtonClass = function(paid) {
        return paid ? "btn-success" : "btn-danger";
    };

    $scope.getButtonText = function(paid) {
        return paid ? "Paid" : "Unpaid";
    };
});
