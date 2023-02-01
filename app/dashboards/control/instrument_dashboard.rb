require 'belongs_to_field'

require "administrate/base_dashboard"

class Control::InstrumentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:         Field::Number,
    symbol:     Field::String,
    name:       Field::String,
    volumes:    Field::String.with_options(searchable: false),
    store_id:   DisableTextField.with_options(default: :current_store),
    trace:      Fields::BelongsToField.with_options(associated: :store),
    account:    Fields::BelongsToField.with_options(associated: :store),
    created_at: Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at: Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  symbol
  name
  account
  created
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  symbol
  name
  account
  volumes
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  symbol
  name
  account
  store_id
  volumes
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

  # Overwrite this method to customize how instruments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(instrument)
  #   "Instrument ##{instrument.id}"
  # end
end
