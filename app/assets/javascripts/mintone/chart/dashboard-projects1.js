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
    // ==============================================================
    // Our Income
    // ==============================================================
    // var chart = c3.generate({
    //     bindto: '#memory_usage',
    //     data: {
    //         columns: [
    //             ['date', 0, 0, 0],
    //             ['capital', 0, 0, 0],
    //             ['profit', 0, 0, 0]
    //         ],
    //         type: 'bar'
    //     },
    //     bar: {
    //         space: 0.1,
    //         // or
    //         width: 20 // this makes bar width 100px
    //     },
    //     axis: {
    //         y: {
    //             tick: {
    //                 count: 4,
    //                 outer: false
    //             }
    //         }
    //     },
    //     legend: {
    //         hide: true
    //         //or hide: 'data1'
    //         //or hide: ['data1', 'data2']
    //     },
    //     grid: {
    //         x: {
    //             show: true
    //         },
    //         y: {
    //             show: true
    //         }
    //     },
    //     size: {
    //         height: 300
    //     },
    //     color: {
    //         pattern: ['#ffb74e', '#fe365f', '4782fa']
    //     }
    // });

    // var data_chart = $('#memory_usage-chart-monthy_amount').data('chart');
    // setTimeout(function() {
    //     chart.load({
    //         columns: data_chart
    //         // columns: [
    //         //     ['Growth Income', 512, 200, 100],
    //         //     ['Income', 315, 150, 50],
    //         //     ['Net Income', 197, 110, 30]
    //         // ]
    //     });
    // }, 1500);

});


