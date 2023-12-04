# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = '1.0'

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path
# Add Yarn node_modules folder to the asset load path.
Rails.application.config.assets.paths << Rails.root.join('node_modules')
Rails.application.config.assets.paths << Rails.root.join('app', 'javascript', 'controllers')


# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
Rails.application.config.assets.precompile += %w( application.js stisla.css stripe.scss mintone.css mintone.js saasley.css saasley.js)
Rails.application.config.assets.precompile += ['application.js', 'controllers/index.js', 'controllers/application.js', 
	'foundation_emails/foundation_emails.css', 'controllers/hello_controller.js' , 'jquery.session.js']
Rails.application.config.assets.precompile += %w( saasley/theme.bundle.js mintone_chart.js mintone/morris.css  mintone/chart/apexcharts.min.js)
Rails.application.config.assets.precompile += %w( mintone/select2.min.css mintone/select2.full.min.js mintone/chart/morris.js mintone/chart/jquery.sparkline.min.js mintone/chart/raphael-min.js)
Rails.application.config.assets.precompile += %w( mintone/moment.min.js )
Rails.application.config.assets.precompile += %w( modernize.css modernize.js modernize/apexcharts.css js_modernize)


# Add node_modules folder to the asset load path.
Rails.application.config.assets.paths << Rails.root.join("node_modules")
