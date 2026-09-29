// Shakapacker's preset covers preset-env, runtime transform and the
// class-properties / object-rest-spread syntax the old Webpacker config listed.
module.exports = function (api) {
  const defaultConfigFunc = require('shakapacker/package/babel/preset.js')
  return defaultConfigFunc(api)
}
