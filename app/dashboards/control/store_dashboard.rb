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
    url:           Field::String,
    state:                  Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    dashboard_restrict:     Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    email:         Field::String.with_options(searchable: false),
    plan:                   Field::BelongsTo,
    plan_items:             Field::HasMany,
    language:               Field::Select.with_options(collection: Store::LANGUAGE),
    contact_whatsapp:       Field::String.with_options(searchable: false),
    telegram_bot_chat_id:   Field::String.with_options(searchable: false),
    telegram_bot_status:    Field::String.with_options(searchable: false),
    telegram_bot_token:     Field::String.with_options(searchable: false),
    resource_system:        Field::Text,
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
  state
  name
  plan
  url
  email
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  state
  dashboard_restrict
  name
  email
  contact_whatsapp
  plan
  url
  language
  ].freeze


  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  state
  dashboard_restrict
  name
  email
  contact_whatsapp
  url
  plan
  language
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
