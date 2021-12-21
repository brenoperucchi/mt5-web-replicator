const { environment } = require('@rails/webpacker')

module.exports = environment

const { environment } = require('@rails/webpacker')

const fileLoader = environment.loaders.get('file')
fileLoader.exclude = /node_modules[\\/]quill/

const svgLoader = {
  test: /\.svg$/,
  loader: 'svg-sprite-loader',
  include: [
    resolve('node_modules/flag-icon-css/flags/'),
  ]
}
  
  environment.loaders.prepend('svg', svgLoader)

module.exports = environment