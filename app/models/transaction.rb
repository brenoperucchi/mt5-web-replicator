require "#{Rails.root}/lib/telegram/signal"
class Transaction < ApplicationRecord
  belongs_to :order
  belongs_to :message

  scope :closed, ->{where(state: 'closed')}
  scope :not_closed, ->{where.not(state: ['closed', 'error'])}
  scope :finish, ->{where(state: ['closed', 'error'])}
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
        if order.transactions.count > 1 and first_transaction?
          order.transactions.where.not(id: order.transactions.finish.map(&:id)).each do |transc|
            transc.set_sl_and_tp_order(take_profit=0, stop_loss=self.price_open) unless meta_get_closed_ticket_position(self.order.trace, transc.ticket)
          end
        end
      end

      def update_state(state)
        self.order.close
        self.update(close_at: DateTime.now)
      end
    end
  end

  def first_transaction?
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
      # self.erro
    else
      true
    end
  end

end