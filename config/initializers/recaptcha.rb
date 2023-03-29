Recaptcha.configure do |config|
  Recaptcha.configuration.skip_verify_env.delete("test")

  config.site_key   = '6LdU9j0lAAAAAJEVhjw8tvaot15E36qMYqBIczb_'
  config.secret_key = '6LdU9j0lAAAAAPwg7JGMU128M7a6vtHq2ogNn55b'
end