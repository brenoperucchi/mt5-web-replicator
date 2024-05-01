require_relative '../../app/fields/has_many_scope_field.rb'
require "administrate/base_dashboard"


class StoreDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                     Field::Number,
    name:                   Field::String,
    url:                    Field::String,
    email:                  Field::String,
    language:               Field::Select.with_options(collection: Store::LANGUAGE),
    state:                  Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    dashboard_restrict:     Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    dashboard_date_filter:  Field::Select.with_options(collection: Store::DATE_FILTER),
    contact_whatsapp:       Field::String.with_options(searchable: false),
    telegram_bot_chat_id:   Field::String.with_options(searchable: false),
    telegram_bot_status:    Field::String.with_options(searchable: false),
    telegram_bot_token:     Field::String.with_options(searchable: false),
    plan:                   Field::BelongsTo,
    payment:                Field::BelongsTo,
    plan_items:             Field::HasMany,
    accounts:               Field::HasMany.with_options(limit:5),
    customers:              Field::HasMany,
    payment_methods:        Field::HasMany,
    users:                  Field::HasMany,
    traces:                 Field::HasMany.with_options(limit:5),
    tag_list:               Field::Tag.with_options(class_name: 'Store', attribute_name: :tag_list),
    created_at:             Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:             Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),

    api_debug_mode:           Field::Boolean.with_options(searchable: false),
    api_debug_mode_level:     Field::Number.with_options(searchable: false),
    api_freeze_max_time:      Field::Number.with_options(searchable: false),
    api_time_to_check_server: Field::Number.with_options(searchable: false),
    api_time_max_seconds:     Field::Number.with_options(searchable: false),
    api_slippage:             Field::Number.with_options(searchable: false),
    api_environment_local:    Field::Boolean.with_options(searchable: false),
    api_store_state:          Field::Boolean.with_options(searchable: false),
    api_store_message:        Field::String.with_options(searchable: false),
    api_milliseconds_timer:   Field::Number.with_options(searchable: false),
    api_milliseconds_tick:    Field::Number.with_options(searchable: false),
    api_event_on_timer:       Field::Boolean.with_options(searchable: false),
    api_event_on_tick:        Field::Boolean.with_options(searchable: false),
    api_mfe_mae_display:      Field::Boolean.with_options(searchable: false),
    api_reach_mfe_target:     Field::Number.with_options(searchable: false),
    api_reach_loss_set:       Field::Number.with_options(searchable: false),
    api_send_orders_history:  Field::Boolean.with_options(searchable: false),
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
  id
  name
  url
  state
  plan
  dashboard_date_filter
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  state
  dashboard_restrict
  dashboard_date_filter
  name
  email
  url
  language
  contact_whatsapp
  telegram_bot_chat_id
  telegram_bot_status
  telegram_bot_token
  tag_list
  plan
  plan_items
  accounts
  traces
  customers
  users
  payment
  payment_methods
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
  state
  dashboard_restrict
  dashboard_date_filter
  name
  email
  url
  language
  contact_whatsapp
  telegram_bot_chat_id
  telegram_bot_status
  telegram_bot_token
  tag_list
  plan
  plan_items
  accounts
  payment
  payment_methods
  ].freeze

  FORM_ATTRIBUTES_ADVANCED = %i[
  api_debug_mode
  api_debug_mode_level
  api_freeze_max_time
  api_time_to_check_server
  api_time_max_seconds
  api_slippage
  api_environment_local
  api_store_state
  api_store_message
  api_milliseconds_timer
  api_milliseconds_tick
  api_event_on_timer
  api_event_on_tick
  api_mfe_mae_display
  api_reach_mfe_target
  api_reach_loss_set
  api_send_orders_history
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
  def display_resource(store)
    store.try(:url)
  end

end