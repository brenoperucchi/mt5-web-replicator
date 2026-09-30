require "administrate/field/base"

# Renders a credential (API key, webhook secret, bot token) without ever
# exposing its value: index/show pages get "••••" + the last 4 characters,
# and the form gets an empty password input. Blank submissions are dropped
# by Admin::ApplicationController#resource_params, so leaving the input
# empty keeps the stored value.
class SecretField < Administrate::Field::Base
  VISIBLE_CHARS = 4

  def self.searchable?
    false
  end

  def masked
    value = data.to_s
    return I18n.t("administrate.fields.secret.not_set", default: "not set") if value.blank?
    return "••••" if value.length <= VISIBLE_CHARS * 2

    "••••#{value[-VISIBLE_CHARS..]}"
  end

  def to_s
    masked
  end
end
