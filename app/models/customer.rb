class Customer < ApplicationRecord

  attr_writer :email

  store :settings, accessors: [:role, :stripe_product_id, :stripe_customer_id]
  
  belongs_to :store
  has_many :users, as: :userable#, dependent: :destroy
  has_many :accounts
  has_many :invoices, as: :invoiceable#, dependent: :destroy

  pay_customer

  validates_presence_of :name

  accepts_nested_attributes_for :users

  def email
    users.try(:first).try(:email)
  end

  def create_invoice(name = nil)
    name = name.blank? ? "#{self.id}-#{Time.zone.now.strftime("%Y-%m")}" : name 
    invoice = invoices.find_or_create_by(name: name)
    invoice.items.find_or_create_by(name: :monthly_payment) do |item|
       item.amount = store.plan_value
    end
    if store.plan_percent.present?
      amount = self.accounts.slave.sum(&:balance_month)
      amount_total = (amount.to_f * (store.plan_percent.to_f / 100))
      
      description = "Invoice #{name}\r\n\n"
      self.accounts.slave.map do |account|
        account.slaves.map do |slave|
          description << "Date: #{I18n.l slave.created_at, format: :short} - Ticket #{slave.ticket_slave} - Symbol:#{slave.symbol} - Profit:#{slave.profit}\r\n" if slave.profit != 0
        end
      end

      description << "Slaves closed count: #{self.accounts.slave.sum(&:balance_month_count)}\r\n"
      description << "Amount:#{amount.to_f} * Plan Percent:#{store.plan_percent.to_f / 100} = #{amount_total}\r\n"
      invoice.items.find_or_create_by(name: :profit_percent,  amount: amount_total, description: description) 
    end

    invoice.balance_update

    # invoices.find_or_create_by(name: name) do |invoice| 
    #   # invoice.amount = amount
    #   invoice.email = email
    # end
  end


end
