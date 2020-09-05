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

ActiveRecord::Schema.define(version: 2020_09_01_013709) do

  create_table "apisocials", force: :cascade do |t|
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "clients", force: :cascade do |t|
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "posts", force: :cascade do |t|
    t.string "title"
    t.text "body"
    t.boolean "published"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "signs", force: :cascade do |t|
    t.string "provider"
    t.string "provider_name"
    t.string "action"
    t.string "kind"
    t.string "symbol"
    t.string "price_request"
    t.string "price_open"
    t.string "stop_loss"
    t.string "take_profit_1"
    t.string "take_profit_2"
    t.string "comment"
    t.string "lots"
    t.string "magic"
    t.string "ticket"
    t.text "context"
    t.datetime "open_at"
    t.string "response"
    t.string "response_value"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "signal_id"
    t.string "provider"
    t.string "provider_name"
    t.string "action"
    t.string "kind"
    t.string "symbol"
    t.string "price"
    t.string "price_open"
    t.string "stop_loss"
    t.string "take_profit_1"
    t.string "take_profit_2"
    t.string "comment"
    t.string "lots"
    t.string "magic"
    t.string "ticket"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["signal_id"], name: "index_transactions_on_signal_id"
  end

end
