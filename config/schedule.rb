# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
set :output, "log/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever


every 1.minute do # 1.minute 1.day 1.week 1.month 1.year is also supported
  # the following tasks are run in parallel (not in sequence)
  runner "Invoice.generate_month_customers"
end

# # Tarefas de manutenção do sistema
# every 1.day, at: '3:00 am' do
#   rake "maintenance:manage_orphaned_transactions"
# end

# # Verificação regular de discrepâncias nos cálculos das contas
# every 1.day, at: '4:00 am' do
#   rake "maintenance:check_account_discrepancies"
# end

# # Limpeza de transações órfãs antigas (mais de 30 dias)
# every 1.week, at: '5:00 am' do
#   rake "maintenance:clean_old_orphaned"
# end