# Load DSL and set up stages
require "capistrano/setup"
require 'sshkit/sudo'

# Include default deployment tasks
require "capistrano/deploy"
require 'capistrano/rbenv'
require 'capistrano/puma'
install_plugin Capistrano::Puma::Systemd
require 'capistrano/bundler'
require 'capistrano/rails/assets'
require 'capistrano/rails/migrations'
# require 'capistrano3/unicorn'
require 'capistrano/sidekiq'
require 'capistrano/yarn'
require "capistrano/scm/git"
install_plugin Capistrano::SCM::Git

# Load custom tasks from `lib/capistrano/tasks` if you have any defined
Dir.glob("lib/capistrano/tasks/*.rake").each { |r| import r }