require "administrate/base_dashboard"
module Message
  class MessageDashboard < Administrate::BaseDashboard
    # ATTRIBUTE_TYPES
    # a hash that describes the type of each of the model's fields.
    #
    # Each different type represents an Administrate::Field object,
    # which determines how the attribute is displayed
    # on pages throughout the dashboard.
    ATTRIBUTE_TYPES = {
      id:           Field::Number,
      content:      Field::Text.with_options(searchable: true),
      params:       Field::Text.with_options(searchable: true),
      content_id:   Field::String,
      state:        Field::String,
      kind:         Field::String,
      response:     Field::String,
      traces:       Field::HasMany,
      orders:       Field::HasMany,
      slaves:       Field::HasMany.with_options(class_name: 'TransactionSlave'),
      all_loggings: Field::HasMany.with_options(class_name: 'Logging', limit:30),
      # message: Field::HasOne,
      updated_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
      created_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
      content_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
      prepare_at:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    }.freeze

    # COLLECTION_ATTRIBUTES
    # an array of attributes that will be displayed on the model's index page.
    #
    # By default, it's limited to four items to reduce clutter on index pages.
    # Feel free to add, remove, or rearrange items.
    COLLECTION_ATTRIBUTES = %i[
    id
    state
    kind
    all_loggings
    traces
    orders
    slaves
    created_at
    updated_at

    ].freeze

    # SHOW_PAGE_ATTRIBUTES
    # an array of attributes that will be displayed on the model's show page.
    SHOW_PAGE_ATTRIBUTES = %i[
    state
    all_loggings
    traces
    orders
    slaves
    params
    content
    content_at
    created_at
    ].freeze

    # FORM_ATTRIBUTES
    # an array of attributes that will be displayed
    # on the model's form (`new` and `edit`) pages.
    FORM_ATTRIBUTES = %i[
    state
    traces
    content
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
end