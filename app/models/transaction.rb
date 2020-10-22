class Transaction < ApplicationRecord
  belongs_to :order

  state_machine :initial => :pending do
    # after_transition :pending => :executed, :do => :update_state
    after_transition :pending => :executed, :do => :update_state
    after_transition [:pending, :executed] => :error, :do => :update_state
    # after_transition [:executed, :ordered] => :pending, :do => :update_state

    event :execute do
      transition :pending => :executed
    end
    event :erro do
      transition [:pending, :executed] => :error
    end
    event :cancel do
      transition [:executed, :error] => :pending
    end
    state :error do
      def update_state(state)
        self.order.erro
      end
    end
    state :executed do
      def update_state(state)
        self.order.execute
      end
    end
  end
end
