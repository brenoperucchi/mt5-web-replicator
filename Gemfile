def next?
  File.basename(__FILE__) == 'Gemfile.next'
end
source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '2.7.8'

# Bundle edge Rails instead: gem 'rails', github: 'rails/rails'
gem 'rails', '~> 6.1.7.8'
# Use sqlite3 as the database for Active Record
# Use Puma as the app server
gem 'puma', '>= 6.4.1'
# Use SCSS for stylesheets
gem 'sass-rails', '~> 5'
# Transpile app-like JavaScript. Read more: https://github.com/rails/webpacker
gem 'webpacker', '~> 6.0.0.rc.6'
# Turbolinks makes navigating your web application faster. Read more: https://github.com/turbolinks/turbolinks
gem 'turbolinks', '~> 5'
# Build JSON APIs with ease. Read more: https://github.com/rails/jbuilder
gem 'jbuilder', '~> 2.7'
# Use Redis adapter to run Action Cable in production
# gem 'redis', '~> 4.0'
# Use Active Model has_secure_password
# gem 'bcrypt', '~> 3.1.7'

gem 'bundler', '2.4.20'

# Use Active Storage variant
# gem 'image_processing', '~> 1.2'

# Reduces boot times through caching; required in config/boot.rb
gem 'rake', '>= 13.0.6'
gem 'bootsnap', '>= 1.6.0' #, require: false

group :development, :test do
  # Call 'byebug' anywhere in the code to stop execution and get a debugger console
  # gem 'byebug'#, platforms: [:mri, :mingw, :x64_mingw]
  gem 'sqlite3', '~> 1.4'
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
  gem "minitest"
end


group :development do
  # Access an interactive console on exception pages or by calling 'console' anywhere in the code.
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  # Spring speeds up development by keeping your application running in the background. Read more: https://github.com/rails/spring
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.1'
  gem "better_errors"
  gem "binding_of_caller"
  gem 'pry', '~> 0.14.1'  
  gem 'pry-byebug'
  gem "debug", ">= 1.0.0"
  # gem 'pry-rails'#, :group => :development, github: "TigerWolf/pry-rails"
  # gem 'pry-byebug'
  # gem 'pry-nav'
  # gem 'pry-stack_explorer'
  # gem 'annotate'

  gem 'ruby-debug-ide'
  gem 'debase',' >= 0.2.5.beta2'
  gem 'rubocop'
  gem 'foreman'
  gem 'capistrano', '~> 3.6'
  gem 'capistrano-rails'
  gem 'capistrano-bundler'
  gem 'capistrano-rbenv'
  gem 'capistrano3-puma', '6.0.0.beta.1'
  gem 'sshkit-sudo'
  # gem 'capistrano-sidekiq'#, git: 'http://github.com/seuros/capistrano-sidekiq'
  gem 'capistrano-sidekiq', '2.3.0'
  gem 'capistrano-yarn'
  gem "rename"
  gem 'bcrypt_pbkdf', '~> 1'
  gem 'ed25519', '~> 1.2'
  gem "lol_dba"
  # gem 'html2slim', '0.2.3', path: 'vendor/html2slim'
  gem 'html2slim', '0.2.3', git: 'https://github.com/brenoperucchi/html2slim.git'
end

gem 'pg', '1.4.5'
gem 'wannabe_bool'
gem 'acts-as-taggable-on', '~> 7.0'
gem 'administrate-field-acts_as_taggable'
gem 'ancestry'
gem 'paper_trail', '13.0.0'
gem 'devise'
gem "font-awesome-rails"
gem 'jquery-rails'
gem "rest-client"
gem 'pay'
gem 'stripe', '~> 9'
gem 'mercadopago-sdk'
gem 'dotenv'

# # To use Braintree + PayPal, also include:
# gem 'braintree', '>= 4.4', '< 5.0'
# gem 'paddle_pay', '~> 0.1'
gem 'receipts', '~> 2'
gem 'next_rails'
gem 'telegram-bot-ruby'
gem 'sidekiq', '7.1.3'
gem 'pundit'
gem 'simple_form'
gem 'sd_notify'
# gem 'newrelic_rpm'
gem 'recaptcha'
gem 'link_thumbnailer'
gem 'imgix'
gem "net-http"
gem 'money-rails', '~> 1.12'

#API
gem 'grape'  
gem 'grape-active_model_serializers'
gem 'grape_on_rails_routes'
gem 'rack-cors' 
gem 'eventmachine'
gem 'slim'
gem "tinymce-rails", '~> 4.4', '>= 4.4.3'

# ADMINISTRATE
# gem "administrate",         path: "vendor/administrate"
# gem 'administrate-field-tag',       path: 'vendor/administrate-field-tag/'
# gem 'administrate_ransack', path: "vendor/administrate_ransack"
# gem "administrate",         git: 'https://github.com/thoughtbot/administrate.git', tag:'v0.18.0'
# gem "administrate", path: "vendor/administrate"
# gem 'administrate-field-scoped_has_many', path: "vendor/administrate-field-scoped_has_many"
gem "administrate",                 git: 'https://github.com/brenoperucchi/administrate.git', branch: '0.18.0'
gem 'administrate-field-image'
gem 'administrate-field-tag',       git: 'https://github.com/brenoperucchi/administrate-field-tag.git', branch: 'main'
gem "administrate-field-nested_has_many"
gem 'administrate_ransack',         git: "https://github.com/brenoperucchi/administrate_ransack.git", branch: 'master'
gem "administrate-field-tinymce",   git: 'https://github.com/smedrick/administrate-field-tinymce.git'
gem 'administrate-field-active_storage'
gem "image_processing"
# ADMINISTRATE

gem 'rtesseract'  
gem 'state_machine', git: 'https://github.com/shopperplus/state_machine.git'
gem 'lucky_case'
gem 'ruby_linear_regression'
gem 'whenever', require: false


# gem 'ocr_space', path: "vendor/ocr_space"
# gem 'state_machine', git: 'https://github.com/Edfinity/state_machine.git'
# gem 'state_machine',   git: 'https://github.com/brenoperucchi/state_machine'
# gem 'state_machine', path: 'vendor/state_machine3'
# Stylesheet inlining for email **
# gem 'inky-rb', require: 'inky'
# gem 'premailer-rails'