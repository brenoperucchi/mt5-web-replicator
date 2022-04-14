require "administrate/base_dashboard"

class Control::StoreDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:            Field::Number,
    name:          Field::String,
    state:         Field::String,
    plan:          Field::String,
    plan_value:    Field::String,
    plan_percent:  Field::String,
    volume_default:         Field::String,
    stripe_webhook_secret:  Field::String,
    stripe_api_secret:      Field::String,
    tag_list:               Field::Tag.with_options(class_name: 'Store', attribute_name: :tag_list),
    created_at:             Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:             Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  name
  state
  plan
  tag_list
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  name
  state
  plan
  plan_value
  plan_percent
  tag_list
  volume_default
  stripe_api_secret
  stripe_webhook_secret
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how mains are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(main)
  #   "Main ##{main.id}"
  # end
end
