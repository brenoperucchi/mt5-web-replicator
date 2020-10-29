FactoryBot.define do
  factory :order do
    trait :m15_trace do
      message_id { 723517440 }
      message { "BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39" }
      photo_path { "#{Rails.root}/tmp/500028400464_282900.jpg" }
      name { "RoboSignal" }
      name_id { "-481414224" }
    end
  end
end