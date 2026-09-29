namespace :billing do
  desc 'Repoint stores, customer plans and open invoices from MercadoPago to Stripe (DRY_RUN=1 to preview)'
  task migrate_mercadopago_to_stripe: :environment do
    dry_run = ENV['DRY_RUN'].present? && ENV['DRY_RUN'] != '0'
    Billing::MercadoPagoToStripe.new(dry_run: dry_run).call
  end
end
