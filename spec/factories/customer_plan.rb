FactoryBot.define do
  factory :customer_plan do
    kind { :fixed }
    charge_recurrence { :monthly }
    amount { 50.0 }
    due_at_dates { 5 }
    
    # Associações opcionais
    store { nil }
    payment { nil }
    
    # Adicione outros atributos necessários para os testes
    trait :premium do
      amount { 100.0 }
    end
  end
end
