$(function() {
    "use strict";
    var data_chart = $('#morris-area-chart').data('chart');
    console.log(data_chart);
    Morris.Area({
        element: 'morris-area-chart',
        data: data_chart,
        xkey: 'day',
        ykeys: ['portfolio'],
        labels: ['portfolio'],
        pointSize: 2,
        fillOpacity: 0,

        pointStrokeColors: ['#f95476', '#ffb74e', '#4886ff'],
        behaveLikeLine: true,
        gridLineColor: '#e0e0e0',
        lineWidth: 2,
        hideHover: 'auto',
        lineColors: ['#f95476', '#ffb74e', '#4886ff'],
        resize: true

    });
});
