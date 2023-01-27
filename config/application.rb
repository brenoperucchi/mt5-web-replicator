require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Signalforex
  class Application < Rails::Application

    config.action_mailer.default_url_options = { host: "imentore.com.br" }


    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.1
    config.time_zone = 'America/Sao_Paulo'
    config.autoloader = :zeitwerk
    config.active_record.yaml_column_permitted_classes = [Symbol, Date, ActiveSupport::HashWithIndifferentAccess]

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
   	##API
   	# config.paths.add File.join('app', 'api'), glob: File.join('**', '*.rb')
   	# config.autoload_paths += Dir[Rails.root.join('app', 'api', '*')]
    # config.autoload_paths += Dir[Rails.root.join('lib')]
    config.autoload_paths += Dir[Rails.root.join('app','fields', '*')]
    # config.autoload_paths << "#{Rails.root}/app/fields"
    # config.autoload_paths += Dir[Rails.root.join('app','controllers', 'concerns')]
    config.autoload_paths << "#{Rails.root}/app/controllers/concerns"
    config.eager_load_paths << "#{Rails.root}/app/controllers/concerns"
    # config.autoload_paths << "#{Rails.root}/app/fields"
    # config.eager_load_paths << "#{Rails.root}/app/fields"


    # /Users/brenoperucchi/Devs/signalforex/app/fields/has_many_scope_field.rb
   	config.middleware.insert_before 0, Rack::Cors do
   	  allow do
   	    origins '*'
   	    resource '*', headers: :any, methods: [:get, :post, :put, :delete, :options]
   	  end
   	end
    #SIDEKIQ
    config.active_job.queue_adapter = :sidekiq
  end
end
