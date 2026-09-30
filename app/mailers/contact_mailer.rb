class ContactMailer < ApplicationMailer
  default from: -> { ENV.fetch('MAIL_FROM', 'contato@imentore.com.br') }
  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.contact_mailer.email.subject
  #
  def email(user, password=nil)
    if Rails.env.production? && ENV['SMTP_ADDRESS'].present?
      delivery_options = { user_name: ENV['SMTP_USERNAME'],
                           password: ENV['SMTP_PASSWORD'],
                           address: ENV['SMTP_ADDRESS'],
                           port: ENV.fetch('SMTP_PORT', '587') }
    end

    @user = user
    @password = password
    mail to: user.email, delivery_method_options: delivery_options, subject: "Seja Bem Vindo ao Imentore Copy"
  end
end
