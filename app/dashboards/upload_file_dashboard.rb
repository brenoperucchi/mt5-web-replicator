require "administrate/base_dashboard"

class UploadFileDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:              Field::Number,
    file:            Field::ActiveStorage,
    file_content:    Field::Text.with_options(searchable: false),
    uploadable:      Field::Polymorphic.with_options(searchable: false),
    filename:        Field::String.with_options(searchable: false),
    account:         Field::String.with_options(searchable: false),
    kind:            Field::Select.with_options(collection: [:none, :import]),
    store:           Field::BelongsTo,
    trace:           Field::BelongsTo,

  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  store
  trace
  account
  uploadable
  kind
  filename
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  store
  trace
  account
  uploadable
  file_content
  kind
  file
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  store
  trace
  kind
  file
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
