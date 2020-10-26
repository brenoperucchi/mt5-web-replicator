# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `rails
# db:schema:load`. When creating a new database, `rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2020_10_26_052605) do

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.integer "record_id", null: false
    t.integer "blob_id", null: false
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
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "apisocials", force: :cascade do |t|
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.integer "user_id"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["user_id"], name: "index_clients_on_user_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "state"
    t.string "message"
    t.string "message_response"
    t.string "message_id"
    t.datetime "active_at"
    t.datetime "ready_at"
    t.datetime "execute_at"
    t.integer "trace_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "image"
    t.string "symbol"
    t.string "kind"
    t.index ["trace_id"], name: "index_orders_on_trace_id"
  end

  create_table "slaves", force: :cascade do |t|
    t.integer "trace_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "environment"
    t.index ["trace_id"], name: "index_slaves_on_trace_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "name"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.text "settings"
  end

  create_table "traces", force: :cascade do |t|
    t.string "name"
    t.string "name_id"
    t.datetime "active_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "store_id"
    t.text "settings"
  end

  create_table "transactions", force: :cascade do |t|
    t.string "state"
    t.string "ticket"
    t.decimal "profit"
    t.integer "order_id"
    t.string "action"
    t.string "kind"
    t.string "symbol"
    t.string "price_request"
    t.string "price_open"
    t.string "stop_loss"
    t.string "take_profit"
    t.string "comment"
    t.string "lot"
    t.string "magic"
    t.string "response"
    t.string "response_error"
    t.datetime "open_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "meta_order_generate"
    t.index ["order_id"], name: "index_transactions_on_order_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
end
