require "administrate/base_dashboard"

class CustomerPlanDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                 Field::Number,
    name:               Field::String,
    amount:             Field::String,
    amount_discount:    Field::String,
    kind:               CheckboxField.with_options(object:"customer", collection_key: CustomerPlan.kinds.keys, default: :fixed),
    charge_recurrence:  CheckboxField.with_options(object:"customer", collection_key: CustomerPlan.charge_recurrences.keys, default: :monthly),
    meta_margin_mode:   CheckboxField.with_options(object:"customer", collection_key: (Account.meta_margin_modes.keys + ["both"]), default: :hedging),
    meta_mode:          CheckboxField.with_options(object:"customer", collection_key: (Account.meta_modes.keys + ["both"]), default: :demo),
    discount_behavior:  CheckboxField.with_options(object:"customer", collection_key: CustomerPlan::ENUM_discount_behavior, default: :always),
    store:              Field::BelongsTo,
    customers:          Field::HasMany,
    accounts:           Field::HasMany,
    traces:             Field::HasMany,
    customers:          Field::HasMany,
    created_at:         Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:         Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    name
    amount
    kind
    customers
    store
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    amount
    kind
    amount_discount
    discount_behavior
    charge_recurrence
    meta_margin_mode
    meta_mode
    store
    customers
    accounts
    traces
    created_at
    updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    name
    amount
    kind
    amount_discount 
    discount_behavior
    store
    customers
    accounts
    traces
    charge_recurrence
    meta_margin_mode
    meta_mode
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
