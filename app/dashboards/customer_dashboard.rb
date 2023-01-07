require "administrate/base_dashboard"

class CustomerDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    name:                 Field::String,
    email:                Field::String,
    stripe_customer_id:   Field::String,
    stripe_product_id:    Field::String,
    role:                 Field::String,
    role_control:         CheckboxField.with_options(object:"customer", collection_key: :CONTROL_ROLE, default: :admin),
    store:                Field::BelongsTo,
    user:                 Field::HasOne,
    customer_plan:        Field::BelongsTo,
    accounts:             Field::HasMany,
    invoices:             Field::HasMany,
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
  email
  role
  role_control
  accounts
  user
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  name
  email
  role
  role_control
  stripe_customer_id
  stripe_product_id
  store
  user
  customer_plan
  accounts
  invoices
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  role
  role_control
  stripe_customer_id
  stripe_product_id
  store
  user
  customer_plan
  accounts
  invoices
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
