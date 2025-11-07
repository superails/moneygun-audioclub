class ConvertConnectedAccountsToPolymorphicOwner < ActiveRecord::Migration[8.0]
  def up
    # Add polymorphic owner columns
    add_column :connected_accounts, :owner_type, :string
    add_column :connected_accounts, :owner_id, :bigint

    # Migrate existing data: set owner_type to 'User' and owner_id to user_id
    execute <<-SQL
      UPDATE connected_accounts
      SET owner_type = 'User', owner_id = user_id
      WHERE user_id IS NOT NULL
    SQL

    # Make owner columns not null after data migration
    change_column_null :connected_accounts, :owner_type, false
    change_column_null :connected_accounts, :owner_id, false

    # Remove foreign key constraint on user_id
    remove_foreign_key :connected_accounts, :users

    # Remove old index on user_id
    remove_index :connected_accounts, :user_id

    # Remove user_id column
    remove_column :connected_accounts, :user_id

    # Add index on polymorphic owner
    add_index :connected_accounts, [ :owner_type, :owner_id ]
  end

  def down
    # Add user_id column back (nullable initially)
    add_reference :connected_accounts, :user, null: true, foreign_key: true

    # Migrate data back: set user_id from owner_id where owner_type is 'User'
    execute <<-SQL
      UPDATE connected_accounts
      SET user_id = owner_id
      WHERE owner_type = 'User'
    SQL

    # Delete any records that aren't User-owned (can't be migrated back)
    execute <<-SQL
      DELETE FROM connected_accounts
      WHERE owner_type != 'User' OR owner_type IS NULL
    SQL

    # Now make user_id not null after cleanup
    change_column_null :connected_accounts, :user_id, false

    # Remove polymorphic columns
    remove_index :connected_accounts, [ :owner_type, :owner_id ]
    remove_column :connected_accounts, :owner_type
    remove_column :connected_accounts, :owner_id
  end
end
