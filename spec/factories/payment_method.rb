FactoryBot.define do
  factory :payment_method do
    trait :stripe do
      name { 'Stripe' }
      handle { 'stripe' }
    end
    trait :mercadopago do
      name { 'Mercado Pago' }
      handle { 'mercado_pago' }
    end
  end
end