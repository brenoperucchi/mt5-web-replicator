$(function() {
    "use strict";
    var data_chart = $('#morris-area-chart-dashboard_capital_accumulated').data('chart');
    Morris.Line({
        element: 'morris-area-chart-dashboard_capital_accumulated',
        data: data_chart,
        xkey: 'day',
        ykeys: ['portfolio', 'profit', 'loss'],
        labels: ['Portfolio', 'Profit', 'Loss'],
        pointSize: 2,
        fillOpacity: 0,

        pointStrokeColors: [ '#3580B8', '#ffb74e', '#94313e'],
        behaveLikeLine: true,
        gridLineColor: '#e0e0e0',
        lineWidth: 2,
        hideHover: 'auto',
        lineColors: [ '#3580B8', '#ffb74e', '#94313e'],
        resize: true

    });
    var data_chart = $('#morris-area-chart-dashboard_drawdown').data('chart');
    Morris.Bar({
        element: 'morris-area-chart-dashboard_drawdown',
        data: data_chart,
        xkey: 'day',
        ykeys: ['drawdown'],
        labels: ['Drawdown'],
        pointSize: 2,
        fillOpacity: 0,

        pointStrokeColors: ['#3580B8', '#ffb74e', '#4886ff'],
        behaveLikeLine: true,
        gridLineColor: '#e0e0e0',
        lineWidth: 2,
        hideHover: 'auto',
        lineColors: ['#3580B8', '#ffb74e', '#4886ff'],
        resize: true

    });
    var data_chart = $("#morris-area-chart-dashboard_monthy_amount").data('chart');
    Morris.Bar({
        element: 'morris-area-chart-dashboard_monthy_amount',
        data: data_chart,
        xkey: 'date',
        ykeys: ['profit', 'capital'],
        labels: ['Profit', 'Capital'],
        pointSize: 2,
        fillOpacity: 0,

        pointStrokeColors: ['#ffb74e', '#3580B8', '4886ff'],
        behaveLikeLine: true,
        gridLineColor: '#e0e0e0',
        lineWidth: 2,
        hideHover: 'auto',
        barColors: ['#ffb74e', '#3580B8', '#4886ff'],
        resize: true

    });
});


