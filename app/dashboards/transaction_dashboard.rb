require "administrate/base_dashboard"

class TransactionDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                 Field::Number,
    ticket:             Field::String,
    state:              Field::String,
    profit:             Field::String.with_options(searchable: false),
    ordertype:          Field::String,
    symbol:             Field::String,
    price_request:      Field::String,
    price_open:         Field::String,
    price_closed:       Field::String,
    stop_loss:          Field::String,
    take_profit:        Field::String,
    comment:            Field::String,
    lot:                Field::String,
    magic_number:       Field::String,
    response:           Field::String,
    response_error:     Field::String,
    open_at:            Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    created_at:         Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:         Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    order:              Field::BelongsTo,
    trace:              Field::BelongsTo,
    message:            Field::BelongsTo,
    account:            Field::BelongsTo,
    loggings:           Field::HasMany,
    slaves:             Field::HasMany.with_options(class_name:'TransactionSlave'),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  ticket
  state
  symbol
  trace
  profit
  account
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  trace
  order
  ticket
  state
  profit
  ordertype
  symbol
  price_request
  price_open
  price_closed
  stop_loss
  take_profit
  comment
  lot
  magic_number
  response
  response_error
  open_at
  created_at
  updated_at
  message
  loggings
  account
  slaves
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  trace
  order
  ticket
  state
  profit
  ordertype
  symbol
  price_request
  price_open
  price_closed
  stop_loss
  take_profit
  comment
  lot
  magic_number
  response
  response_error
  open_at
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

  # Overwrite this method to customize how transactions are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(transaction)
  #   "Transaction ##{transaction.id}"
  # end
end
