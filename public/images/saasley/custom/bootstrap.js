window.bootstrap = require('bootstrap/dist/js/bootstrap.js');
var toastElList = [].slice.call(document.querySelectorAll('.toast'))
var toastList = toastElList.map(function (toastEl) {
  return new bootstrap.Toast(toastEl)
})



//Modal shown input autoFocus
const myModalEl = document.querySelectorAll('.modal')
myModalEl.forEach(function(el) {
  el.addEventListener('shown.bs.modal', event =>{
    event.preventDefault();
    var input = document.querySelector("[autofocus]");
    input.focus();
  })  
})