require "administrate/base_dashboard"
require 'traces_helper'

class TraceDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                  Field::Number,
    name:                Field::String,
    name_id:             Field::String,
    telegram_option:     Field::String.with_options(searchable: false),
    telegram_image:      Field::Boolean,
    telegram_api_id:     Field::String.with_options(searchable: false),
    telegram_api_hash:   Field::String.with_options(searchable: false),
    telegram_api_number: Field::String.with_options(searchable: false),
    active:              Field::Boolean,
    created_at:          Field::DateTime,
    updated_at:          Field::DateTime,
    store:               Field::BelongsTo,
    meta_host:           Field::String,
    kind:                Field::String,
    # volumes:           Field::ActsAsTaggable,
    response:            Field::String,
    messages:            Field::HasMany.with_options(direction: :desc),
    take_profit_limit:   Field::Number,
    instruments:         Field::HasMany,
    accounts:            Field::HasMany
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  active
  name
  name_id
  kind
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  name
  name_id
  active
  kind
  take_profit_limit
  telegram_option
  telegram_image
  telegram_api_id
  telegram_api_hash
  telegram_api_number
  accounts
  messages
  instruments
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  name_id
  active
  kind
  take_profit_limit
  telegram_option
  telegram_image
  telegram_api_id
  telegram_api_hash
  telegram_api_number
  accounts
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how signs are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(sign)
  #   "Sign ##{sign.id}"
  # end

   def display_resource(resource)
    resource.name
  end
end
