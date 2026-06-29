# Preview all emails at http://localhost:3000/rails/mailers/contact_mailer
class ContactMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/contact_mailer/email
  def email
    user = User.first
    password = Devise.friendly_token.first(6)
    ContactMailer.email(user, password)
  end

end
