require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Signalforex
  class Application < Rails::Application

    config.action_mailer.default_url_options = { host: "imentore.com.br" }


    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0
    config.time_zone = 'Brasilia'
    config.autoloader = :classic

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
   	##API
   	config.paths.add File.join('app', 'api'), glob: File.join('**', '*.rb')
   	config.autoload_paths += Dir[Rails.root.join('app', 'api', '*')]
   	config.middleware.insert_before 0, Rack::Cors do
   	  allow do
   	    origins '*'
   	    resource '*', headers: :any, methods: [:get, :post, :put, :delete, :options]
   	  end
   	end
    #SIDEKIQ
    # config.active_job.queue_adapter = :sidekiq
  end
end
