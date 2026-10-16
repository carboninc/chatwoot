class CreateChannelWappi < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_wappi do |t|
      t.integer :account_id, null: false
      t.string :platform, null: false
      t.string :profile_id, null: false
      t.text :api_token, null: false
      t.text :webhook_secret, null: false
      t.string :provider_status
      t.string :status_reason
      t.datetime :status_checked_at
      t.jsonb :status_metadata, null: false, default: {}
      t.timestamps
    end

    add_index :channel_wappi, :account_id
    add_index :channel_wappi, [:platform, :profile_id], unique: true
  end
end
