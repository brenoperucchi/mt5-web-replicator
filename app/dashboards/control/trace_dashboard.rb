require 'has_many_scope_field.rb'
require "administrate/base_dashboard"
require 'traces_helper'

class Control::TraceDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                       Field::Number,
    name:                     Field::String,
    name_id:                  Field::String,
    telegram_option:          Field::String.with_options(searchable: false),
    telegram_image:           Field::Boolean,
    copy_control_instrument:  Field::Boolean,
    telegram_api_id:          Field::String.with_options(searchable: false),
    telegram_api_hash:        Field::String.with_options(searchable: false),
    telegram_api_number:      Field::String.with_options(searchable: false),
    meta_host:                Field::String,
    response:                 Field::String,
    active:                   Field::Boolean,
    kind:                     DisableTextField.with_options(value:"copy"),
    # volumes:                Field::ActsAsTaggable,
    # messages:               Fields::HasManyScopeField.with_options(associated: :store, direction: :desc, sort_by: :created_at),
    store_id:                 DisableAssociation.with_options(attribute: :store),
    take_profit_limit:        DisableTextField.with_options(value:2),
    instruments:              Fields::HasManyScopeField.with_options(associated: :store, scoped: :enable),
    orders:                   Fields::HasManyScopeField.with_options(associated: :trace, scoped: :enable),
    accounts:                 Fields::HasManyScopeField.with_options(associated: :store),
    created_at:               Field::DateTime,
    updated_at:               Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  name
  name_id
  active
  kind
  accounts
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  active
  name
  name_id
  kind
  take_profit_limit
  accounts
  orders
  instruments
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  active
  name
  name_id
  kind
  store_id
  take_profit_limit
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
