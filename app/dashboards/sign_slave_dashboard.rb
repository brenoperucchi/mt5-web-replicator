require "administrate/base_dashboard"

class SignSlaveDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    provider: Field::String,
    provider_name: Field::String,
    symbol: Field::String,
    action: Field::String,
    kind: Field::String,
    price_request: Field::String.with_options(searchable: false),
    price_open: Field::String.with_options(searchable: false),
    stop_loss: Field::String.with_options(searchable: false),
    take_profit_2: Field::String.with_options(searchable: false),
    take_profit_1: Field::String.with_options(searchable: false),
    comment: Field::String,
    lots: Field::String,
    magic: Field::String,
    open_at: Field::DateTime,
    ticket: Field::String,
    context: Field::String,
    response: Field::String,
    response_value: Field::String,
    environment: Field::String,
    service_id: Field::Number,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  symbol
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  provider
  provider_name
  symbol
  action
  kind
  price_request
  price_open
  stop_loss
  take_profit_1
  take_profit_2
  comment
  lots
  magic
  open_at
  ticket
  context
  response
  response_value
  environment
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  symbol
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
end
