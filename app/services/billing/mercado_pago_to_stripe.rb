module Billing
  # Moves every store off legacy payment providers (MercadoPago) onto Stripe.
  #
  # For each store it ensures a Stripe Payment exists (credentials left blank,
  # so the STRIPE_* ENV fallback applies) and repoints the store, its customer
  # plans and its open invoices (pending/to_paid) from legacy payments to it,
  # clearing the stale payment link of repointed invoices. Legacy
  # PaymentMethod/Payment rows are kept: destroying them would cascade and
  # wipe history. Idempotent; with dry_run nothing is written.
  class MercadoPagoToStripe
    OPEN_STATES = %w[pending to_paid].freeze

    attr_reader :dry_run, :summary

    def initialize(dry_run: false, io: $stdout)
      @dry_run = dry_run
      @io = io
      @summary = Hash.new(0)
    end

    def call
      stripe_method = PaymentMethod.find_by(handle: 'stripe')
      if stripe_method.nil?
        summary[:stripe_payment_method_created] += 1
        stripe_method = PaymentMethod.create!(name: 'Stripe', handle: 'stripe') unless dry_run
      end

      legacy_ids = Payment.where.not(payment_method_id: PaymentMethod.available.select(:id)).ids

      Store.find_each do |store|
        ActiveRecord::Base.transaction { migrate_store(store, stripe_method, legacy_ids) }
      end

      report
      summary
    end

    private

    def migrate_store(store, stripe_method, legacy_ids)
      stripe = stripe_method && Payment.find_by(store_id: store.id, payment_method_id: stripe_method.id)
      if stripe.nil?
        summary[:stripe_payments_created] += 1
        return count_only(store, legacy_ids) if dry_run
        stripe = Payment.create!(store: store, payment_method: stripe_method)
      end
      return count_only(store, legacy_ids) if dry_run

      if legacy_ids.include?(store.payment_id)
        store.update_column(:payment_id, stripe.id)
        summary[:stores_repointed] += 1
      end

      summary[:customer_plans_repointed] +=
        CustomerPlan.where(store_id: store.id, payment_id: legacy_ids).update_all(payment_id: stripe.id)

      open_invoices(store, legacy_ids).find_each do |invoice|
        invoice.payment = stripe
        invoice.payment_link = nil
        invoice.save!(validate: false)
        summary[:invoices_repointed] += 1
      end
    end

    def count_only(store, legacy_ids)
      summary[:stores_repointed] += 1 if legacy_ids.include?(store.payment_id)
      summary[:customer_plans_repointed] += CustomerPlan.where(store_id: store.id, payment_id: legacy_ids).count
      summary[:invoices_repointed] += open_invoices(store, legacy_ids).count
    end

    def open_invoices(store, legacy_ids)
      Invoice.where(store_id: store.id, payment_id: legacy_ids, state: OPEN_STATES)
    end

    def report
      prefix = dry_run ? '[DRY RUN] would have' : 'Done:'
      @io.puts "#{prefix} " + %i[stripe_payment_method_created stripe_payments_created stores_repointed
                                 customer_plans_repointed invoices_repointed]
                                .map { |key| "#{key}=#{summary[key]}" }.join(', ')
    end
  end
end
