require "#{Rails.root}/lib/telegram/signal"
class Transaction < ApplicationRecord
  belongs_to :order
  belongs_to :message

  scope :closed, ->{where(state: 'closed')}
  scope :not_closed, ->{where.not(state: 'closed')}
  scope :executed, ->{where(state: 'executed')}

  state_machine :initial => :pending do
    after_transition :pending => :executed, :do => :update_state
    after_transition :pending => :executed, :do => :update_state
    after_transition :executed => :closed, :do => :update_state
    after_transition :executed => :closed, :do => :break_even
    after_transition [:pending, :executed, :closed] => :error, :do => :update_state
    # after_transition [:executed, :ordered] => :pending, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :close do
      transition :executed => :closed
    end
    event :cancel do
      transition [:executed, :error, :closed] => :pending
    end
    event :erro do
      transition [:pending, :executed, :closed] => :error
    end
    
    state :error do
      def update_state(state)
        self.order.erro
      end
    end
    state :executed do
      def update_state(state)
        self.order.execute
      	meta_get_open_positions(self, self.order.trace)
      end
    end
    state :closed do
      def break_even(state)
        transactions = order.transactions.executed
        first_id = transactions.first
        transactions.each do |transaction|
          unless transaction.first?
            set_sl_and_tp_order(take_profit=self.price_request, stop_loss=self.price_request)
          end
        end
      end

      def update_state(state)
        self.order.close
        self.update(close_at: DateTime.now)
      end
    end
  end

  def first?
  	order.transactions.first == self
  end

  def close_order
    response, response_error = meta_close_order(self.ticket, self.order.trace)
    if response > 0
      self.update_columns(response_error: response_error, state: :closed)
      self.erro
    else
      true
    end
  end

  def set_sl_and_tp_order(take_profit=nil, stop_loss=nil)
    response, response_error = meta_set_sl_and_tp_order(ticket=self.ticket, take_profit=take_profit, stop_loss=stop_loss, trace=self.order.trace)
    if response > 0
      self.update_column(:response_error, response_error)
      self.erro
    else
      true
    end
  end

end