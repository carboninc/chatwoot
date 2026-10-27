class CreateClientFeedRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :client_feed_requests do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.references :message, null: false, index: { unique: true }
      t.string :request_id, null: false
      t.timestamps
    end
    add_index :client_feed_requests, [:account_id, :user_id, :request_id], unique: true, name: 'index_client_feed_requests_on_send_key'
  end
end
