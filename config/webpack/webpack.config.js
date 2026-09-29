// Shakapacker entrypoint: delegate to the per-environment config.
const env = process.env.NODE_ENV || 'development'

module.exports = require(`./${env}`)
