class Customer < ApplicationRecord

  attr_writer :email

  store :settings, accessors: [:role]
  
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
    name = name.blank? ? Time.zone.now.strftime("%Y-%m") : name 
    amount = self.accounts.slave.sum(&:balance_month)
    invoices.find_or_create_by(name: name) do |invoice| 
      invoice.amount = amount
      invoice.email = email
    end
  end


end
