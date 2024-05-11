require 'has_many_scope_field'
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
    id:                       Field::Number.with_options(searchable: true),
    name:                     Field::String,
    name_id:                  Field::String,
    telegram_option:          Field::String.with_options(searchable: false),
    telegram_image:           Field::Boolean.with_options(searchable: false),
    instrument_control:       Field::Boolean.with_options(searchable: false),
    magic_same:               Field::Boolean.with_options(searchable: false),
    telegram_api_id:          Field::String.with_options(searchable: false),
    telegram_api_hash:        Field::String.with_options(searchable: false),
    telegram_api_number:      Field::String.with_options(searchable: false),
    magics_accept:            Field::String.with_options(searchable: false),
    meta_host:                Field::String,
    response:                 Field::String,
    capital_recomendation:    Field::String.with_options(searchable: false),
    capital_multiplier:       Field::String.with_options(searchable: false),
    contract_volume_max:      Field::String.with_options(searchable: false),
    # stock_kind:               CheckboxField.with_options(object:"account", collection_key: Account.stock_kinds.keys, default: :b3),
    active:                   Field::Boolean,
    kind:                     DisableTextField.with_options(value:"copy", type:'hide'),
    # volumes:                Field::ActsAsTaggable,
    # messages:               Fields::HasManyScopeField.with_options(associated: :store, direction: :desc, sort_by: :created_at),
    store_id:                 DisableAssociation.with_options(attribute: :store, type:'hide'),
    take_profit_limit:        DisableTextField.with_options(value:2, type:'hide'),
    instruments:              Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control'),
    orders:                   Fields::HasManyScopeField.with_options(associated: :trace, dashboard:'control', direction: :desc, sort_by: :created_at),
    accounts:                 Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control', scoped: :not_deleted),
    # customer_plan:            Fields::BelongsToField.with_options(associated: :store, dashboard:'control'),
    customer_plans:           Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control'),
    desc_contract:            Field::Tinymce,
    desc_finish:              Field::Tinymce,
    created_at:               Field::DateTime,
    updated_at:               Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  active
  name
  name_id
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  name
  id
  active
  instrument_control
  kind
  magic_same
  name_id
  magics_accept
  capital_recomendation
  capital_multiplier
  contract_volume_max
  customer_plans
  desc_contract
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  active
  instrument_control
  kind
  magic_same
  name_id
  magics_accept
  capital_recomendation
  capital_multiplier
  contract_volume_max
  store_id
  desc_contract
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
