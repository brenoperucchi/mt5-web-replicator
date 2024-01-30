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
    id:                    Field::Number.with_options(searchable: true),
    name:                  Field::String,
    name_id:               Field::String,
    telegram_option:       Field::String.with_options(searchable: false),
    telegram_image:        Field::Boolean,
    telegram_api_id:       Field::String.with_options(searchable: false),
    telegram_api_hash:     Field::String.with_options(searchable: false),
    telegram_api_number:   Field::String.with_options(searchable: false),
    active:                Field::Boolean.with_options(searchable: false),
    instrument_control:    Field::Boolean.with_options(searchable: false),
    magic_same:            Field::Boolean.with_options(searchable: false),
    store:                 Field::BelongsTo,
    meta_host:             Field::String,
    kind:                  CheckboxField.with_options(collection_key: Trace.kinds.keys, default: :copy),
    kind_copy:             CheckboxField.with_options(collection_key: Trace.kind_copies.keys, default: :normal),
    response:              Field::String,
    capital_recomendation: Field::String.with_options(searchable: false),
    capital_multiplier:    Field::String.with_options(searchable: false),
    contract_volume_max:   Field::String.with_options(searchable: false),
    # stock_kind:            CheckboxField.with_options(object:"account", collection_key: Account.stock_kinds.keys, default: :b3),
    take_profit_limit:     Field::String.with_options(searchable: false),
    magics_accept:         Field::String.with_options(searchable: false),
    # volumes:             Field::ActsAsTaggable,
    messages:              Field::HasMany.with_options(direction: :desc, limit: 5),
    instruments:           Field::HasMany,
    accounts:              Field::HasMany,
    customer_plans:        Field::HasMany,
    transactions:          Field::HasMany,
    desc_contract:         Field::Tinymce,
    desc_finish:           Field::Tinymce,
    created_at:            Field::DateTime,
    updated_at:            Field::DateTime,
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
  kind_copy
  store
  accounts
  transactions
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  active
  instrument_control
  kind
  kind_copy
  magic_same
  name
  name_id
  magics_accept
  capital_recomendation
  capital_multiplier
  contract_volume_max
  store
  accounts
  customer_plans
  messages
  instruments
  transactions
  created_at
  updated_at
  ].freeze
  # take_profit_limit
  # telegram_option
  # telegram_image
  # telegram_api_id
  # telegram_api_hash
  # telegram_api_number

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  active
  instrument_control
  kind
  kind_copy
  magic_same
  name_id
  magics_accept
  capital_recomendation
  capital_multiplier
  contract_volume_max
  store
  accounts
  customer_plans
  desc_contract
  desc_finish
  ].freeze

  # take_profit_limit
  # telegram_option
  # telegram_image
  # telegram_api_id
  # telegram_api_hash
  # telegram_api_number
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
