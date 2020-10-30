FactoryBot.define do
  factory :order do
    trait :m15_trace_first do
      message_id { 111 }
      message { "BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39" }
      image { Rack::Test::UploadedFile.new("#{Rails.root}/tmp/500028400464_282900.jpg", 'image/jpg') } 
    end

    trait :m15_trace_second do
      m15_trace_first
      message_id { 222 }
      message { "BUY 80.39\n\nTP 80.19\nTP 79.89\nTP 79.39\nSL 81.39" }
      image { Rack::Test::UploadedFile.new("#{Rails.root}/tmp/500028400464_282900.jpg", 'image/jpg') } 
    end
  end
end