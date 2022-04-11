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
      invoice.items.find_or_create_by(name: :profit_percent,  amount: (amount.to_f * (store.plan_percent.to_f / 100))) 
    end

    invoice.balance_update

    # invoices.find_or_create_by(name: name) do |invoice| 
    #   # invoice.amount = amount
    #   invoice.email = email
    # end
  end


end
