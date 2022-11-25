require_relative '../../app/fields/has_many_scope_field.rb'
require "administrate/base_dashboard"


class StoreDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:     Field::Number,
    name:   Field::String,
    state:  Field::String,
    url:    Field::String,
    # plan:          Field::String,
    volume_default:         Field::String,
    telegram_bot_chat_id:   Field::String,
    telegram_bot_status:    Field::String,
    telegram_bot_token:     Field::String,
    stripe_webhook_secret:  Field::String,
    stripe_api_secret:      Field::String,
    plan:       Field::BelongsTo,
    accounts:   Field::HasMany,
    # accounts:   Fields::HasManyScopeField.with_options(scoped: :enable),
    traces:     Field::HasMany,
    customers:  Field::HasMany,
    users:      Field::HasMany,
    traces:     Field::HasMany,
    tag_list:   Field::Tag.with_options(class_name: 'Store', attribute_name: :tag_list),
    created_at: Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at: Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  name
  state
  plan
  telegram_bot_chat_id
  telegram_bot_status
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  name
  state
  url
  telegram_bot_chat_id
  telegram_bot_status
  telegram_bot_token
  tag_list
  volume_default
  stripe_api_secret
  stripe_webhook_secret
  plan
  accounts
  traces
  customers
  users

  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  state
  url
  telegram_bot_chat_id
  telegram_bot_status
  telegram_bot_token
  tag_list
  plan
  accounts
  volume_default
  stripe_api_secret
  stripe_webhook_secret
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how mains are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(main)
  #   "Main ##{main.id}"
  # end
end
