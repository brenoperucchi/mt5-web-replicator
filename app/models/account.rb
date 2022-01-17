class Account < ApplicationRecord
  
  after_create :insert_instruments

  enum state: {disable: 0, enable: 1}
  enum kind:  {slave: 0, copy: 1}

  store :settings, accessors: [:magics_accept]

  belongs_to :store
  has_many :permissions
  has_many :traces,       through: :permissions#, source: :trace 
  has_many :orders,       through: :traces, source: :orders

  has_many :loggings,      as: :loggerable, dependent: :destroy
  has_many :transactions,  class_name: 'Transaction',      foreign_key: 'account_id'
  has_many :slaves,        class_name: 'TransactionSlave', foreign_key: 'account_id'
  has_many :instruments,   dependent: :destroy

  def trace_copy
    traces.find_by(kind: :copy) if self.copy?
  end

  def sum_slaves_volume(transaction_id)
    slaves.joins(:master).where("transaction_slaves.transaction_id=#{transaction_id}", account_id:self.id).map(&:lot).map(&:to_f).reduce(:+)
  end

  def insert_instruments
    if self.slave?
      Instrument::SYMBOLLIST.each do |symbol|
        self.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes])
      end
    end
  end

  def instrument_volume(symbol, value=0)
    instrument = instruments.find_by(symbol: symbol)
    begin
      instrument.volumes.try(:split,', ')[value]
    rescue
      store.volume_default
    end
  end


end