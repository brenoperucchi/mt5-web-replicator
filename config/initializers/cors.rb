Rails.application.config.middleware.insert_before 0, Rack::Cors do
# /Users/brenoperucchi/Devs/signalforex/app/fields/has_many_scope_field.rb
  allow do
    origins '*'
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head]
  end
end