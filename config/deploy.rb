# config valid only for current version of Capistrano
lock "3.14.1"

set :application, 'signalforex'
set :repo_url, 'git@github.com:brenoperucchi/signalforex.git'

# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }.call
set :branch, "master"
set :log_level, :debug

set :use_sudo, false
set :bundle_binstubs, nil
set :linked_files, fetch(:linked_files, []).push('config/database.yml')
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle', 'public/system', 'public/uploads')

set :rbenv_type, :user # or :system, depends on your rbenv setup
set :rbenv_ruby, '2.6.6'

# in case you want to set ruby version from the file:
# set :rbenv_ruby, File.read('.ruby-version').strip

set :rbenv_prefix, "RBENV_ROOT=#{fetch(:rbenv_path)} RBENV_VERSION=#{fetch(:rbenv_ruby)} #{fetch(:rbenv_path)}/bin/rbenv exec"
set :rbenv_map_bins, %w{rake gem bundle ruby rails}
set :rbenv_roles, :all # default value

set :unicorn_rack_env, 'production'

after 'deploy:publishing', 'deploy:restart'
namespace :deploy do
  task :add_default_hooks do
    after 'deploy:starting'#, 'sidekiq:start'
    after 'deploy:updated'#, 'sidekiq:stop'
    after 'deploy:reverted'#, 'sidekiq:stop'
    after 'deploy:published'#, 'sidekiq:start'
  end
  
  task :restart do
    invoke 'unicorn:stop'
    on roles(:app) do
       # execute "systemctl --user stop sidekiq.service"
    end
    invoke 'unicorn:start'
    on roles(:app) do
      # execute "systemctl --user start sidekiq.service"
      execute "systemctl --user restart python-signal-api.service"
      execute "systemctl --user restart python-signal-order.service"
    #   execute "RBENV_ROOT=$HOME/.rbenv RBENV_VERSION=2.6.6 $HOME/.rbenv/bin/rbenv exec bundle exec sidekiq --pidfile /home/bperucchi/app/shared/tmp/pids/sidekiq-0.pid --environment production --logfile /home/bperucchi/app/shared/log/sidekiq.log --config /home/bperucchi/app/shared/config/sidekiq.yml --daemon"
    end
  end
end
# Default branch is :master
# ask :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# Default deploy_to directory is /var/www/my_app_name
# set :deploy_to, "/var/www/my_app_name"

# Default value for :format is :airbrussh.
# set :format, :airbrussh

# You can configure the Airbrussh format using :format_options.
# These are the defaults.
# set :format_options, command_output: true, log_file: "log/capistrano.log", color: :auto, truncate: :auto

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
# append :linked_files, "config/database.yml", "config/secrets.yml"

# Default value for linked_dirs is []
# append :linked_dirs, "log", "tmp/pids", "tmp/cache", "tmp/sockets", "public/system"

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for local_user is ENV['USER']
# set :local_user, -> { `git config user.name`.chomp }

# Default value for keep_releases is 5
# set :keep_releases, 5
