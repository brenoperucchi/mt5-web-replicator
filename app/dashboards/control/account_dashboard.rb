require 'has_many_scope_field'
require "administrate/base_dashboard"

class Control::AccountDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                   Field::Number.with_options(searchable: true),
    name:                 Field::String,
    state:                Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    kind:                 CheckboxField.with_options(object:"customer", collection_key: Account.kinds.keys.reverse, default: :slave),
    meta_margin_mode:     CheckboxField.with_options(object:"customer", collection_key: Account.meta_margin_modes.keys.reverse, default: :hedging),
    meta_mode:            CheckboxField.with_options(object:"customer", collection_key: Account.meta_modes.keys, default: :demo),
    contract_volume:      Field::String.with_options(searchable: false),
    # stock_kind:           CheckboxField.with_options(object:"account", collection_key: Account.stock_kinds.keys, default: :b3, searchable: false),
    traces:               Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control', scoped: :not_deleted),
    slaves:               Fields::HasManyScopeField.with_options(dashboard:'control', direction: :desc, sort_by: :created_at),
    instruments:          Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control'),
    store:                Field::BelongsTo,
    customer:             Field::BelongsToField.with_options(associated: :store, dashboard:'control'),
    account_server:       Field::BelongsTo,
    magics_accept:        Field::String.with_options(searchable: false),
    instrument_control:   Field::Boolean,
    created_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  COLLECTION_ATTRIBUTES = %i[
  name
  customer
  state
  kind
  traces
  slaves
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  state
  name
  kind
  meta_mode
  meta_margin_mode
  instrument_control
  contract_volume
  magics_accept
  account_server
  customer
  store
  traces
  slaves
  instruments
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.

  # FORM_ATTRIBUTES_NEW = %i[
  # state
  # name
  # kind
  # meta_mode
  # meta_margin_mode
  # instrument_control
  # contract_volume
  # magics_accept
  # customer
  # traces
  # ].freeze

  FORM_ATTRIBUTES = %i[
  state
  name
  kind
  meta_mode
  meta_margin_mode
  instrument_control
  contract_volume
  magics_accept
  customer
  traces
  account_server
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