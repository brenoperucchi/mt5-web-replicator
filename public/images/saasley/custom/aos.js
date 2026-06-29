//Aos animation + Countup on aos-init
const AOS = require('aos');
AOS.init({
  startEvent: 'load',
  duration: 600,
  delay: 50,
  once: true,
  easing:'ease-in-out-quart'
});
