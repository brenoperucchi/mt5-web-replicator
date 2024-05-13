FactoryBot.define do

  factory :store do
    name { "Store 1" }
    active_at { DateTime.current }
    state { 1 }
    email { 'user@store1.com' }
    url { 'store1' }
    tag_list { "" }
    volume_default {0.10} 
    telegram_api_id { '980209'} 
    telegram_api_hash {'03062326232cb23c6770e7a735c2dae2'} 
    telegram_api_number {'5548984222627'} 

    after(:create) do |store, evaluator|
      payment_method = store.payment_methods.create(name: 'Mercado Pago', handle: 'mercado_pago')
      payment_method.payments.first.update(api_token: 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627', webhook_token: 'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a')
      payment_method = store.payment_methods.create(name: 'Stripe',       handle: 'stripe')
      payment_method.payments.last.update(api_token: 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627', webhook_token: 'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a')
    end


    after(:create) do |store, evaluator|
      store.customer_plans.create(name: :plan1, kind:0, amount:100, payment: store.payments.first, due_at_dates: 5)
      store.update(payment_id: 1)
    end

    trait :store2 do
      name { "Store 2" }
      active_at { DateTime.current }
      email { 'user@store2.com' }
      url { 'store2' }
      tag_list { "" }
      volume_default {0.10} 
      telegram_api_id { '980209'} 
      telegram_api_hash {'03062326232cb23c6770e7a735c2dae2'} 
      telegram_api_number {'5548984222627'} 


      after(:create) do |store, evaluator|
        payment_method = store.payment_methods.create(name: 'Mercado Pago', handle: 'mercado_pago')
        payment_method.payments.first.update(api_token: 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627', webhook_token: 'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a')
        payment_method = store.payment_methods.create(name: 'Stripe',       handle: 'stripe')
        payment_method.payments.last.update(api_token: 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627', webhook_token: 'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a')
      end

      after(:create) do |store, evaluator|
        store.customer_plans.create(name: :plan1, kind:0, amount:100, amount_discount:30, payment: store.payments.first, due_at_dates: 5)
        store.update(payment_id: 1)
      end

    end
  end
end