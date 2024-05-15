# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2024_05_15_173343) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "account_servers", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "accounts", force: :cascade do |t|
    t.string "name"
    t.bigint "store_id"
    t.text "settings"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "state", default: 0
    t.integer "kind", default: 0
    t.integer "meta_margin_mode", default: 0
    t.integer "meta_mode", default: 0
    t.bigint "customer_id"
    t.integer "stock_kind", default: 0
    t.datetime "deleted_at"
    t.bigint "account_server_id"
    t.index ["account_server_id"], name: "index_accounts_on_account_server_id"
    t.index ["customer_id"], name: "index_accounts_on_customer_id"
    t.index ["store_id"], name: "index_accounts_on_store_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "balances", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "slave_id"
    t.bigint "master_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "order_id"
    t.index ["account_id"], name: "index_balances_on_account_id"
    t.index ["master_id"], name: "index_balances_on_master_id"
    t.index ["order_id"], name: "index_balances_on_order_id"
    t.index ["slave_id"], name: "index_balances_on_slave_id"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.bigint "user_id"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "customer_plans", force: :cascade do |t|
    t.string "name"
    t.decimal "amount", precision: 10, scale: 2
    t.bigint "store_id", null: false
    t.text "settings"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.datetime "active_at"
    t.integer "kind", default: 0
    t.integer "charge_recurrence", default: 1
    t.bigint "payment_id"
    t.index ["payment_id"], name: "index_customer_plans_on_payment_id"
    t.index ["store_id"], name: "index_customer_plans_on_store_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "name"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "settings"
    t.bigint "store_id"
    t.bigint "customer_plan_id"
    t.integer "role", default: 0
    t.integer "role_control", default: 0
    t.datetime "deleted_at"
    t.index ["customer_plan_id"], name: "index_customers_on_customer_plan_id"
    t.index ["deleted_at"], name: "index_customers_on_deleted_at"
    t.index ["store_id"], name: "index_customers_on_store_id"
  end

  create_table "deals", force: :cascade do |t|
    t.string "state"
    t.string "symbol"
    t.string "ticket"
    t.bigint "account_id"
    t.bigint "store_id"
    t.bigint "trace_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_deals_on_account_id"
    t.index ["store_id"], name: "index_deals_on_store_id"
    t.index ["trace_id"], name: "index_deals_on_trace_id"
  end

  create_table "instruments", force: :cascade do |t|
    t.string "symbol"
    t.string "name"
    t.bigint "trace_id"
    t.string "volumes"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "account_id"
    t.bigint "store_id"
    t.index ["account_id"], name: "index_instruments_on_account_id"
    t.index ["store_id"], name: "index_instruments_on_store_id"
    t.index ["trace_id"], name: "index_instruments_on_trace_id"
  end

  create_table "invoice_items", force: :cascade do |t|
    t.string "name"
    t.text "settings"
    t.decimal "amount", precision: 10, scale: 2, default: "0.0"
    t.bigint "invoice_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "description"
    t.bigint "account_id"
    t.bigint "trace_id"
    t.integer "state", default: 0
    t.bigint "plan_usage_id"
    t.index ["account_id"], name: "index_invoice_items_on_account_id"
    t.index ["invoice_id"], name: "index_invoice_items_on_invoice_id"
    t.index ["plan_usage_id"], name: "index_invoice_items_on_plan_usage_id"
    t.index ["trace_id"], name: "index_invoice_items_on_trace_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.string "name"
    t.integer "state", default: 0
    t.string "invoiceable_type"
    t.bigint "invoiceable_id"
    t.decimal "amount"
    t.text "settings"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "stripe_invoice_id"
    t.bigint "store_id"
    t.bigint "payment_id"
    t.bigint "plan_usage_id"
    t.text "response"
    t.datetime "due_at"
    t.integer "kind", default: 0
    t.index ["invoiceable_type", "invoiceable_id"], name: "index_invoices_on_invoiceable"
    t.index ["payment_id"], name: "index_invoices_on_payment_id"
    t.index ["plan_usage_id"], name: "index_invoices_on_plan_usage_id"
    t.index ["store_id"], name: "index_invoices_on_store_id"
  end

  create_table "loggings", force: :cascade do |t|
    t.string "content"
    t.bigint "user_id"
    t.string "loggerable_type"
    t.bigint "loggerable_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "changeset"
    t.integer "version_id"
    t.string "state"
    t.string "resourceable_type"
    t.bigint "resourceable_id"
    t.bigint "account_id"
    t.string "ancestry", collation: "C"
    t.text "settings"
    t.index ["account_id"], name: "index_loggings_on_account_id"
    t.index ["ancestry"], name: "index_loggings_on_ancestry"
    t.index ["loggerable_type", "loggerable_id"], name: "index_loggings_on_loggerable_type_and_loggerable_id"
    t.index ["resourceable_type", "resourceable_id"], name: "index_loggings_on_resourceable"
    t.index ["user_id"], name: "index_loggings_on_user_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.string "content_id"
    t.string "state"
    t.bigint "store_id"
    t.bigint "trace_id"
    t.string "ancestry"
    t.string "response"
    t.datetime "prepare_at"
    t.datetime "content_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "account_id"
    t.string "state_meta"
    t.text "params"
    t.text "settings"
    t.index ["account_id"], name: "index_messages_on_account_id"
    t.index ["ancestry"], name: "index_messages_on_ancestry"
    t.index ["store_id"], name: "index_messages_on_store_id"
    t.index ["trace_id"], name: "index_messages_on_trace_id"
  end

  create_table "messages_orders", id: false, force: :cascade do |t|
    t.bigint "message_id", null: false
    t.bigint "order_id", null: false
  end

  create_table "messages_traces", force: :cascade do |t|
    t.bigint "trace_id", null: false
    t.bigint "message_id", null: false
    t.index ["message_id"], name: "index_messages_traces_on_message_id"
    t.index ["trace_id"], name: "index_messages_traces_on_trace_id"
  end

  create_table "morphics", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "transaction_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["account_id"], name: "index_morphics_on_account_id"
    t.index ["transaction_id"], name: "index_morphics_on_transaction_id"
  end

  create_table "order_transactions", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "transaction_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["order_id"], name: "index_order_transactions_on_order_id"
    t.index ["transaction_id"], name: "index_order_transactions_on_transaction_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "state"
    t.string "response"
    t.string "content"
    t.integer "content_id"
    t.datetime "active_at"
    t.datetime "ready_at"
    t.datetime "execute_at"
    t.bigint "trace_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "image"
    t.string "symbol"
    t.bigint "message_id"
    t.bigint "account_id"
    t.bigint "store_id"
    t.bigint "deal_id"
    t.index ["account_id"], name: "index_orders_on_account_id"
    t.index ["content_id"], name: "index_orders_on_content_id"
    t.index ["deal_id"], name: "index_orders_on_deal_id"
    t.index ["message_id"], name: "index_orders_on_message_id"
    t.index ["store_id"], name: "index_orders_on_store_id"
    t.index ["trace_id"], name: "index_orders_on_trace_id"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "subscription_id"
    t.string "processor_id", null: false
    t.integer "amount", null: false
    t.string "currency"
    t.integer "application_fee_amount"
    t.integer "amount_refunded"
    t.jsonb "metadata"
    t.jsonb "data"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.jsonb "data"
    t.datetime "deleted_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["owner_type", "owner_id", "deleted_at", "default"], name: "pay_customer_owner_index"
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.jsonb "data"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "processor_id", null: false
    t.boolean "default"
    t.string "type"
    t.jsonb "data"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "name", null: false
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.datetime "trial_ends_at"
    t.datetime "ends_at"
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.jsonb "metadata"
    t.jsonb "data"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.datetime "current_period_start"
    t.datetime "current_period_end"
    t.boolean "metered"
    t.string "pause_behavior"
    t.datetime "pause_starts_at"
    t.datetime "pause_resumes_at"
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.string "processor"
    t.string "event_type"
    t.jsonb "event"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "payment_methods", force: :cascade do |t|
    t.string "name"
    t.string "handle"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "payment_method_id"
    t.bigint "store_id"
    t.string "api_token"
    t.string "webhook_token"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "min_amount"
    t.index ["payment_method_id"], name: "index_payments_on_payment_method_id"
    t.index ["store_id"], name: "index_payments_on_store_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.bigint "account_id"
    t.bigint "trace_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "plan_usage_id"
    t.bigint "customer_plan_id"
    t.index ["account_id"], name: "index_permissions_on_account_id"
    t.index ["customer_plan_id"], name: "index_permissions_on_customer_plan_id"
    t.index ["plan_usage_id"], name: "index_permissions_on_plan_usage_id"
    t.index ["trace_id"], name: "index_permissions_on_trace_id"
  end

  create_table "plan_customers", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "customer_plan_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id"], name: "index_plan_customers_on_customer_id"
    t.index ["customer_plan_id"], name: "index_plan_customers_on_customer_plan_id"
  end

  create_table "plan_items", force: :cascade do |t|
    t.string "name"
    t.boolean "recurrent"
    t.decimal "amount", precision: 10, scale: 2
    t.bigint "plan_id"
    t.text "settings"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "limit", default: 0
    t.index ["plan_id"], name: "index_plan_items_on_plan_id"
  end

  create_table "plan_stores", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "plan_item_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["plan_item_id"], name: "index_plan_stores_on_plan_item_id"
    t.index ["store_id"], name: "index_plan_stores_on_store_id"
  end

  create_table "plan_usages", force: :cascade do |t|
    t.string "description"
    t.integer "quantity"
    t.string "usageable_type", null: false
    t.bigint "usageable_id", null: false
    t.bigint "store_id", null: false
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.datetime "charged_at"
    t.string "resourceable_type"
    t.bigint "resourceable_id"
    t.string "handle"
    t.datetime "disable_at"
    t.text "plan_serializer"
    t.bigint "trace_id"
    t.index ["resourceable_type", "resourceable_id"], name: "index_plan_usages_on_resourceable"
    t.index ["store_id"], name: "index_plan_usages_on_store_id"
    t.index ["trace_id"], name: "index_plan_usages_on_trace_id"
  end

  create_table "plans", force: :cascade do |t|
    t.string "name"
    t.text "settings"
    t.decimal "amount", precision: 10, scale: 2
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.decimal "amount_extra", precision: 10, scale: 2
  end

  create_table "statistics", force: :cascade do |t|
    t.string "name"
    t.decimal "amount", default: "0.0"
    t.integer "kind", default: 0
    t.string "statisticable_type"
    t.bigint "statisticable_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "store_traces", force: :cascade do |t|
    t.bigint "store_id", null: false
    t.bigint "trace_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["store_id"], name: "index_store_traces_on_store_id"
    t.index ["trace_id"], name: "index_store_traces_on_trace_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "name"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "settings"
    t.integer "state", default: 0
    t.string "url"
    t.integer "telegram_bot_chat_id"
    t.bigint "plan_id"
    t.string "email"
    t.bigint "payment_id"
    t.index ["payment_id"], name: "index_stores_on_payment_id"
    t.index ["plan_id"], name: "index_stores_on_plan_id"
  end

  create_table "taggings", id: :serial, force: :cascade do |t|
    t.integer "tag_id"
    t.string "taggable_type"
    t.integer "taggable_id"
    t.string "tagger_type"
    t.integer "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at"
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
  end

  create_table "tags", id: :serial, force: :cascade do |t|
    t.string "name"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.integer "taggings_count", default: 0
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "tokens", force: :cascade do |t|
    t.string "resourceable_type"
    t.bigint "resourceable_id"
    t.string "tokenable_type"
    t.bigint "tokenable_id"
    t.string "name"
    t.text "settings"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["resourceable_type", "resourceable_id"], name: "index_tokens_on_resourceable"
    t.index ["tokenable_type", "tokenable_id"], name: "index_tokens_on_tokenable"
  end

  create_table "traces", force: :cascade do |t|
    t.string "name"
    t.string "name_id"
    t.string "response"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "store_id"
    t.text "settings"
    t.string "meta_host"
    t.text "symbol_list"
    t.integer "kind", default: 0
    t.datetime "deleted_at"
    t.text "mfe_analyzed"
    t.integer "kind_copy", default: 0
  end

  create_table "transaction_slaves", force: :cascade do |t|
    t.bigint "ticket_master"
    t.decimal "profit", default: "0.0"
    t.string "ordertype"
    t.string "symbol"
    t.string "price_request"
    t.string "price_open"
    t.string "stop_loss"
    t.string "take_profit"
    t.string "comment"
    t.string "lot"
    t.string "magic_number"
    t.string "response"
    t.string "response_error"
    t.bigint "transaction_id"
    t.datetime "open_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "state", default: 0
    t.string "ticket_deal"
    t.bigint "account_id"
    t.bigint "ticket_slave"
    t.datetime "closed_at"
    t.string "price_closed"
    t.integer "deal_id"
    t.integer "trace_id"
    t.integer "order_id"
    t.bigint "store_id"
    t.index ["account_id"], name: "index_transaction_slaves_on_account_id"
    t.index ["store_id"], name: "index_transaction_slaves_on_store_id"
    t.index ["transaction_id"], name: "index_transaction_slaves_on_transaction_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.string "state"
    t.bigint "ticket"
    t.decimal "profit", default: "0.0"
    t.bigint "order_id"
    t.string "ordertype"
    t.string "symbol"
    t.string "price_request"
    t.string "price_open"
    t.string "stop_loss"
    t.string "take_profit"
    t.string "comment"
    t.string "lot"
    t.string "magic_number"
    t.string "response"
    t.string "response_error"
    t.datetime "open_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "meta_order_generate"
    t.bigint "message_id"
    t.bigint "account_id"
    t.bigint "trace_id"
    t.string "price_closed"
    t.datetime "closed_at"
    t.integer "deal_id"
    t.integer "ticket_deal"
    t.index ["account_id"], name: "index_transactions_on_account_id"
    t.index ["message_id"], name: "index_transactions_on_message_id"
    t.index ["order_id"], name: "index_transactions_on_order_id"
    t.index ["trace_id"], name: "index_transactions_on_trace_id"
  end

  create_table "upload_files", force: :cascade do |t|
    t.string "uploadable_type"
    t.bigint "uploadable_id"
    t.string "kind"
    t.bigint "store_id"
    t.bigint "trace_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.bigint "account_id"
    t.index ["account_id"], name: "index_upload_files_on_account_id"
    t.index ["store_id"], name: "index_upload_files_on_store_id"
    t.index ["trace_id"], name: "index_upload_files_on_trace_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.bigint "store_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "userable_type"
    t.bigint "userable_id"
    t.index ["email"], name: "index_users_on_email"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["store_id"], name: "index_users_on_store_id"
    t.index ["userable_type", "userable_id"], name: "index_users_on_userable"
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.bigint "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.text "object"
    t.datetime "created_at"
    t.text "object_changes"
    t.bigint "logging_id"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
    t.index ["logging_id"], name: "index_versions_on_logging_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "customer_plans", "stores"
  add_foreign_key "instruments", "accounts"
  add_foreign_key "instruments", "stores"
  add_foreign_key "invoices", "stores"
  add_foreign_key "order_transactions", "orders"
  add_foreign_key "order_transactions", "transactions"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "plan_stores", "plan_items"
  add_foreign_key "plan_stores", "stores"
  add_foreign_key "plan_usages", "stores"
  add_foreign_key "store_traces", "stores"
  add_foreign_key "store_traces", "traces"
  add_foreign_key "stores", "plans"
  add_foreign_key "taggings", "tags"
  add_foreign_key "versions", "loggings"
end
