require 'belongs_to_field'
require 'has_many_scope_field.rb'
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
    kind:                 Field::String,
    meta_mode:            Field::String,
    meta_margin_mode:     Field::String,
    traces:               Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control', scoped: :not_deleted),
    orders:               Fields::HasManyScopeField.with_options(dashboard:'control', direction: :desc, sort_by: :created_at),
    instruments:          Fields::HasManyScopeField.with_options(associated: :store, dashboard:'control'),
    store:                Field::BelongsTo,
    customer:             Fields::BelongsToField.with_options(associated: :store, dashboard:'control'),
    magics_accept:        Field::String.with_options(searchable: false),
    instrument_control:   Field::Boolean,
    created_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  name
  customer
  state
  kind
  traces
  orders
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  state
  kind
  meta_mode
  meta_margin_mode
  magics_accept
  customer
  store
  traces
  orders
  instrument_control
  instruments
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  state
  instrument_control
  name
  customer
  kind
  meta_mode
  meta_margin_mode
  magics_accept
  traces
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