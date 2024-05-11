require "administrate/base_dashboard"

class AccountDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id:                   Field::Number.with_options(searchable: true),
    name:                 Field::String,
    state:                Field::Boolean.with_options(enum:true, checked:"enable", unchecked:"disable"),
    stock_kind:           CheckboxField.with_options(object:"account", collection_key: Account.stock_kinds.keys, default: :b3),
    kind:                 CheckboxField.with_options(object:"customer", collection_key: Account.kinds.keys, default: :fixed),
    meta_margin_mode:     CheckboxField.with_options(object:"customer", collection_key: Account.meta_margin_modes.keys, default: :hedging),
    meta_mode:            CheckboxField.with_options(object:"customer", collection_key: Account.meta_modes.keys, default: :demo),
    contract_volume:      Field::String.with_options(searchable: false),
    traces:               Field::HasMany,
    orders:               Field::HasMany,
    slaves:               Field::HasMany,
    loggings:             Field::HasMany,
    instruments:          Field::HasMany,
    account_server:       Field::BelongsTo,
    store:                Field::BelongsTo,
    customer:             Field::BelongsTo,
    magics_accept:        Field::String.with_options(searchable: false),
    instrument_control:   Field::Boolean,
    created_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    updated_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    deleted_at:           Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"),
    api_send_orders_history_date_start: Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"), 
    api_send_orders_history_date_end:   Field::DateTime.with_options(format: "%d/%m/%Y %H:%M:%S"), 

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
    api_close_all_orders:     Field::Boolean.with_options(searchable: false),
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
  customer
  kind
  meta_mode
  meta_margin_mode
  traces
  orders
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
  id
  name
  customer
  state
  instrument_control
  kind
  meta_mode
  meta_margin_mode
  contract_volume
  magics_accept
  traces
  store
  account_server
  orders
  slaves
  loggings
  instruments
  deleted_at
  created_at
  updated_at
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  
  FORM_ATTRIBUTES = %i[
  name
  customer
  state
  instrument_control
  kind
  meta_mode
  meta_margin_mode
  contract_volume
  magics_accept
  traces
  store
  account_server
  instruments
  deleted_at
  ].freeze

  FORM_ATTRIBUTES_ADVANCED = %i[
  api_store_state
  api_close_all_orders
  api_debug_mode
  api_debug_mode_level
  api_freeze_max_time
  api_time_to_check_server
  api_time_max_seconds
  api_slippage
  api_store_message
  api_send_orders_history_date_start
  api_send_orders_history_date_end
  api_send_orders_history
  api_environment_local
  api_event_on_timer
  api_event_on_tick
  api_mfe_mae_display
  api_reach_mfe_target
  api_reach_loss_set
  api_milliseconds_timer
  api_milliseconds_tick
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
