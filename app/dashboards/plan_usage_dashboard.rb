require "administrate/base_dashboard"

class PlanUsageDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    active_at: Field::DateTime,
    charged_at: Field::DateTime,
    description: Field::String,
    disable_at: Field::DateTime,
    handle: Field::String,
    plan_serializer: Field::Text,
    quantity: Field::Number,
    resourceable: Field::Polymorphic,
    store: Field::BelongsTo,
    trace: Field::BelongsTo,
    usageable: Field::Polymorphic,
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
    active_at
    charged_at
    description
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    active_at
    charged_at
    description
    disable_at
    handle
    plan_serializer
    quantity
    resourceable
    store
    trace
    usageable
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    active_at
    charged_at
    description
    disable_at
    handle
    plan_serializer
    quantity
    resourceable
    store
    trace
    usageable
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

  # Overwrite this method to customize how plan usages are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(plan_usage)
  #   "PlanUsage ##{plan_usage.id}"
  # end
end
