'use strict';
$(document).ready(function() {
    $(function() {
	  $('input[name="daterange"]').daterangepicker({
		opens: 'left'
	  }, function(start, end, label) {
		
	  });
	});
	$(function() {
	  $('input[name="datetimes"]').daterangepicker({
		timePicker: true,
		startDate: moment().startOf('hour'),
		endDate: moment().startOf('hour').add(32, 'hour'),
		locale: {
		  format: 'M/DD hh:mm A'
		}
	  });
	});
	$(function() {
	  $('input[name="birthday"]').daterangepicker({
		singleDatePicker: true,
		showDropdowns: true,
		minYear: 1901,
		maxYear: parseInt(moment().format('YYYY'),10)
	  }, function(start, end, label) {
		var years = moment().diff(start, 'years');
		alert("You are " + years + " years old!");
	  });
	});
	$(function() {

		// var start = moment().subtract(29, 'days');
		// var end = moment();
		var start = moment($('input[name="datefilter"]').val().split(" - ")[0], "DD/MM/YYYY");
		var end = 	moment($('input[name="datefilter"]').val().split(" - ")[1], "DD/MM/YYYY");

		function cb(start, end) {
			$('#reportrange span').html(start.format('DD/MM/YYYY') + ' - ' + end.format('DD/MM/YYYY'));
		}

		$('#reportrange').daterangepicker({
			startDate: start,
			endDate: end,
			autoUpdateInput: false,
		  	locale: {
				format: 'DD/MM/YYYY',
			  	cancelLabel: 'Clear'
			},
			ranges: {
			   'Today': [moment(), moment()],
			   'Yesterday': [moment().subtract(1, 'days'), moment().subtract(1, 'days')],
			   'Last 7 Days': [moment().subtract(6, 'days'), moment()],
			   'Last 30 Days': [moment().subtract(29, 'days'), moment()],
			   'This Month': [moment().startOf('month'), moment().endOf('month')],
			   'Last Month': [moment().subtract(1, 'month').startOf('month'), moment().subtract(1, 'month').endOf('month')]
			}
		}, cb);

		$('#reportrange').on('apply.daterangepicker', function(ev, picker) {
		  $('input[name="datefilter"]').val(picker.startDate.format('DD/MM/YYYY') + ' - ' + picker.endDate.format('DD/MM/YYYY'));
		  // $('#reportrange span').html(start.format('DD/MM/YYYY') + ' - ' + end.format('DD/MM/YYYY'));

		});

		$('#reportrange').on('cancel.daterangepicker', function(ev, picker) {
		  $('input[name="datefilter"]').val('');
		  $('#reportrange span').html('');
		});

		cb(start, end);
	  // $('#reportrange span').html($('input[name="datefilter"]').val());;

	});
	$(function() {
	  $('input[name="datefilter"]').daterangepicker({
		  autoUpdateInput: false,
		  locale: {
		  	  format: 'DD/MM/YYYY',
			  cancelLabel: 'Clear'
		  }
	  });

	  $('input[name="datefilter"]').on('apply.daterangepicker', function(ev, picker) {
		  $(this).val(picker.startDate.format('DD/MM/YYYY') + ' - ' + picker.endDate.format('DD/MM/YYYY'));
	  });

	  $('input[name="datefilter"]').on('cancel.daterangepicker', function(ev, picker) {
		  $(this).val('');
	  });

	});
});