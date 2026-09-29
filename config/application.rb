require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Load .env (see .env.example). The plain `dotenv` gem (2.x) does not load it
# automatically; variables already set in the real environment win.
Dotenv.load if defined?(Dotenv)

module Signalforex
  class Application < Rails::Application

    config.action_mailer.default_url_options = { host: "imentore.com.br" }


    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Rails 7.1 defaults this to false, but our administrate fork
    # (lib/administrate/field/has_many_scope.rb) does `require "sentient_store.rb"`,
    # loading app/models/concerns/sentient_store.rb through $LOAD_PATH. Keep the
    # autoload paths on the load path until that require is removed upstream.
    config.add_autoload_paths_to_load_path = true
    config.time_zone = 'America/Sao_Paulo'
    config.autoloader = :zeitwerk
    # config.active_record.use_yaml_unsafe_load = true

    config.active_record.yaml_column_permitted_classes = [Symbol, Date, ActiveSupport::HashWithIndifferentAccess]

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
   	##API
   	# config.paths.add File.join('app', 'api'), glob: File.join('**', '*.rb')
   	# config.autoload_paths += Dir[Rails.root.join('app', 'api', '*')]
    # config.autoload_paths += Dir[Rails.root.join('lib')]
    # config.autoload_paths += Dir[Rails.root.join('app','fields', '*')]
    # config.autoload_paths += Dir[Rails.root.join('app','controllers', 'concerns', '*')]
    # config.autoload_paths << "#{Rails.root}/app/fields"
    # config.autoload_paths += Dir[Rails.root.join('app','controllers', 'concerns')]
    # config.autoload_paths += Dir[Rails.root.join('app','fields', '*')]


    # config.autoload_paths += %W(#{config.root}/app/controllers/control)
    # config.eager_load_paths += %W(#{config.root}/app/controllers/control)

    # config.autoload_paths += %W(#{config.root}/app/dashboards/control)
    # config.eager_load_paths += %W(#{config.root}/app/dashboards/control)
    
    # config.autoload_paths += %W(#{config.root}/app/models/presenters)
    # config.eager_load_paths += %W(#{config.root}/app/models/presenters)
    # config.autoload_paths << "#{Rails.root}/app/controllers/concerns"
    # config.autoload_paths << "#{Rails.root}/app/presenters"
    # config.eager_load_paths << "#{Rails.root}/app/controllers/concerns"
    # config.eager_load_paths << "#{Rails.root}/app/presenters"
    # config.autoload_paths << "#{Rails.root}/app/fields"
    # config.eager_load_paths << "#{Rails.root}/app/fields"


    #SIDEKIQ
    config.active_job.queue_adapter = :sidekiq
  end
end
