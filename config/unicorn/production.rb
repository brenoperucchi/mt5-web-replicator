# paths
app_path = "/home/bperucchi/app"
working_directory "#{app_path}/current"
pid               "#{app_path}/current/tmp/pids/unicorn.pid"

# listen
listen "/var/tmp/unicorn.sock", backlog: 64

# logging
stderr_path "#{app_path}/shared/log/unicorn.stderr.log"
stdout_path "#{app_path}/shared/log/unicorn.stdout.log"

# workers
worker_processes 3

# use correct Gemfile on restarts
before_exec do |server|
  ENV['BUNDLE_GEMFILE'] = "#{app_path}/current/Gemfile"
end

# preload
preload_app true

before_fork do |server, worker|
  # the following is highly recomended for Rails + "preload_app true"
  # as there's no need for the master process to hold a connection
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.connection.disconnect!
  end

  # Before forking, kill the master process that belongs to the .oldbin PID.
  # This enables 0 downtime deploys.
  old_pid = "#{server.config[:pid]}.oldbin"
  if File.exists?(old_pid) && server.pid != old_pid
    begin
      Process.kill("QUIT", File.read(old_pid).to_i)
    rescue Errno::ENOENT, Errno::ESRCH
      # someone else did our job for us
    end
  end
end

after_fork do |server, worker|
  if defined?(ActiveRecord::Base)
    ActiveRecord::Base.establish_connection
  end
end

# root = "/home/bperucchi/app/current"
# working_directory root

# pid "#{root}/tmp/pids/unicorn.pid"

# stderr_path "#{root}/log/unicorn.log"
# stdout_path "#{root}/log/unicorn.log"

# worker_processes 1
# timeout 30
# preload_app true

# listen '/var/run/unicorn/unicorn.rails_app.sock', backlog: 64

# before_fork do |server, worker|
#   Signal.trap 'TERM' do
#     puts 'Unicorn master intercepting TERM and sending myself QUIT instead'
#     Process.kill 'QUIT', Process.pid
#   end

#   defined?(ActiveRecord::Base) and ActiveRecord::Base.connection.disconnect!

# end

# after_fork do |server, worker|
#   Signal.trap 'TERM' do
#     puts 'Unicorn worker intercepting TERM and doing nothing. Wait for master to send QUIT'
#   end

#   defined?(ActiveRecord::Base) and ActiveRecord::Base.establish_connection
# end

# # Force the bundler gemfile environment variable to
# # reference the capistrano "current" symlink
# before_exec do |_|
#   ENV['BUNDLE_GEMFILE'] = File.join(root, 'Gemfile')
# end