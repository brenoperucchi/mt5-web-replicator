load "#{Rails.root}/lib/telegram/signal.rb"
class Transaction < ApplicationRecord
  belongs_to :order
  belongs_to :message

  scope :closed, ->{where(state: 'closed')}
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
    event :erro do
      transition [:pending, :executed] => :error
    end
    event :close do
      transition :executed => :closed
    end
    event :cancel do
      transition [:executed, :error, :closed] => :pending
    end
    
    state :error do
      def update_state(state)
        self.order.erro
      end
    end
    state :executed do
      def update_state(state)
        self.order.execute
      	meta_opened_order(self, self.order.trace)
      end
    end
    state :closed do
      def break_even(state)
        transactions = order.transactions.executed
        first_id = transactions.first
        if self.first?
          transactions.each do |transaction|
            meta_set_break_env(transaction.ticket, self.price_request, self.order.trace)
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

end
