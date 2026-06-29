import Headroom from "headroom.js";

var stickyHeader = document.querySelectorAll(".navbar-sticky");
stickyHeader.forEach(function(e){
    var headroom  = new Headroom(e);
    headroom.init();
})