require "administrate/base_dashboard"

class OrderDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:           Field::Number.with_options(searchable: true),
    content:      DisableTextField,
    profit_copy:  DisableTextField,
    profit_slave: DisableTextField,
    content_id:   Field::String,
    ordertype:    Field::String,
    state:        Field::String,
    symbol:       Field::String,
    ordertype:    Field::String.with_options(searchable: false),
    trace:        Field::BelongsTo,
    account:      Field::BelongsTo,
    message:      Field::BelongsTo,
    store:        Field::BelongsTo,
    transactions: Field::HasMany,
    slaves:       Field::HasMany,
    messages:     Field::HasMany,
    created_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    ready_at:     Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    execute_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  created_at
  state
  symbol
  content_id
  trace
  account
  profit_copy
  profit_slave
  updated_at
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  state
  symbol
  content_id
  trace
  account
  message
  messages
  profit_copy
  profit_slave
  ordertype
  created_at
  updated_at
  transactions
  slaves
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  state
  symbol
  content
  content_id
  store
  trace

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
