json.extract! client, :id, :name, :user_id, :active_at, :created_at, :updated_at
json.url client_url(client, format: :json)
