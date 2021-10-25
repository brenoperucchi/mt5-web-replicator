source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.2'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.0.3.3'
# Use sqlite3 as the database for Active Record
group :development, :test do
  gem 'sqlite3', '~> 1.4'
  gem 'puma', '~> 3.11'
end
# Use Puma as the app server
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5'
# Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker
gem 'webpacker', '~> 4.0'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', '>= 1.4.2', require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  # gem 'byebug'#, platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  # Access an interactive console on exce   xxxxu9iption pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.1'
end

group :test do
  # Adds support for Capybara system testing and selenium driver

  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  # Easy installation and use of web drivers to run system tests with browsers
  gem 'webdrivers'
  #custom
  gem 'rspec-rails', '~> 4.0.1'
  gem 'guard-rspec'
  gem 'terminal-notifier' , git:"https://github.com/d-a-l-l/terminal-notifier.git"
  gem "database_cleaner"
  gem "factory_bot_rails"


end

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
# gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]


group :development do
  gem "better_errors"
  gem "binding_of_caller"
  gem 'pry', '~> 0.13.1'
  gem 'pry-byebug'
  # gem 'pry-rails'#, :group => :development, github: "TigerWolf/pry-rails"
  # gem 'pry-byebug'
  # gem 'pry-nav'
  # gem 'pry-stack_explorer'
end

# gem 'tdlib-ruby', "2.2.0"

gem 'eventmachine'
gem 'slim'
gem "administrate"
gem 'administrate-field-image'
gem 'administrate-field-tag', git: 'https://github.com/brenoperucchi/administrate-field-tag.git'

gem 'sidekiq'#, '5.2.9'
gem 'sidekiq-scheduler'
gem 'foreman'
# gem 'ocr_space', path: "vendor/ocr_space"
gem 'rtesseract'  
gem 'state_machine', git: 'https://github.com/shopperplus/state_machine.git'
gem 'lucky_case'

#API
gem 'grape'  
gem 'grape-active_model_serializers'
gem 'grape_on_rails_routes'
gem 'rack-cors' 

gem 'capistrano', '~> 3.6'
gem 'capistrano-rails'
gem 'capistrano-bundler'
gem 'capistrano-rbenv'
gem 'capistrano3-unicorn'
# gem 'capistrano-sidekiq'#, git: 'http://github.com/seuros/capistrano-sidekiq'
gem 'capistrano-sidekiq', '1.0.3'

gem 'capistrano-yarn'
gem 'ed25519', '~> 1.2'
gem 'bcrypt_pbkdf', '~> 1'

gem 'postgresql'
gem 'unicorn'
gem "rename"
gem 'wannabe_bool'
gem 'acts-as-taggable-on', '~> 7.0'
gem 'administrate-field-acts_as_taggable'
gem 'ancestry'
gem 'paper_trail'
gem 'pycall'
# gem 'execjs'
# gem "therubyracer"
# gem 'faraday'
# gem 'websocket-client-simple', git:'https://github.com/fuyuton/websocket-client-simple'
# gem 'socket.io-client-simple', git:'https://github.com/fuyuton/ruby-socket.io-client-simple'
# gem 'socketclusterclient'
gem 'ffi-rzmq'