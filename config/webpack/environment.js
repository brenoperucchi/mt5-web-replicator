const { environment } = require('@rails/webpacker')
module.exports = environment

const sassLoader = environment.loaders.get('sass');
const sassLoaderConfig = sassLoader.use.find(el => el.loader === 'sass-loader');

sassLoaderConfig.options = {
  sourceMap: true,
};

environment.loaders.get('sass').use.splice(-1, 0, {
  loader: 'resolve-url-loader',
  options: {
    sourceMap: true,
  },
});

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

// Loader para imagens
environment.loaders.append('images', {
  test: /\.(png|jpe?g|gif|svg)$/i,
  type: 'asset/resource',
  generator: {
    filename: 'images/[hash][ext][query]'
  }
});

// Loader para fontes
environment.loaders.append('fonts', {
  test: /\.(woff|woff2|eot|ttf|otf)$/i,
  type: 'asset/resource',
  generator: {
    filename: 'fonts/[hash][ext][query]'
  }
});

module.exports = environment

const webpack = require("webpack")

environment.plugins.append("Provide", new webpack.ProvidePlugin({
    $: 'jquery',
    jQuery: 'jquery',
    Popper: ['popper.js', 'default']  // Not a typo, we're still using popper.js here
}))
// End new addition

module.exports = environment
