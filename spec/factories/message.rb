FactoryBot.define do
  factory :message, class: 'Message::Message' do
    resource { 'MessageData' }
    content { 'Test message content' }
    source { 'api' }
    handle { 'test_message' }
    
    before(:create) do |message|
      # Criar um log padrão para a mensagem
      message.define_singleton_method(:loggings) do
        Logging.where(loggerable: message)
      end unless message.respond_to?(:loggings)
      
      # Criar um logging principal para a mensagem para que outros logs possam ser associados
      Logging.create(
        content: 'Initial message log',
        state: 'CREATE',
        loggerable: message
      )
    end
  end
end
