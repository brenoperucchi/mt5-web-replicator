require_relative '../../fields/has_many_scope_field.rb'
require_relative '../../fields/belongs_to_field.rb'
require "administrate/base_dashboard"


class Control::CustomerPlanDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    active: Field::Boolean,
    name: Field::String,
    amount: Field::String.with_options(searchable: false),
    store_id: DisableAssociation.with_options(attribute: :store),
    customers: Fields::HasManyScopeField.with_options(associated: :current_store),
    kind: CheckboxField.with_options(object:"customer", collection_key: [:fixed, :percent], default: :fixed),
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
    active
    name
    kind
    amount
    customers
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    active
    name
    kind
    amount
    customers
    store_id
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    active
    name
    kind
    amount
    store_id
    customers
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

  # Overwrite this method to customize how customer plans are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(customer_plan)
  #   "CustomerPlan ##{customer_plan.id}"
  # end
end
