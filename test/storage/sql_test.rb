class SqlTest < Test::Unit::TestCase
  include StorageTests

  DB_FILE = "./xmpp_testcase.db"

  def setup
    ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => DB_FILE)

    ActiveRecord::Schema.define do
      create_table(:xmpp_users, :force => true) do |t|
        t.string(:jid, :limit => 1000, :null => false)
        t.string(:name, :limit => 1000, :null => false)
        t.string(:password, :limit => 1000, :null => false)
      end
      add_index(:xmpp_users, :jid, :unique)

      create_table(:xmpp_contacts, :force => true) do |t|
        t.integer(:xmpp_user_id, :null => false)
        t.string(:jid, :limit => 1000, :null => false)
        t.string(:name, :limit => 1000, :null => false)
        t.string(:ask, :limit => 1000, :null => true)
        t.string(:subscription, :limit => 1000, :null => false)
        t.string(:groups, :limit => 1000, :null => true)
      end
      add_index(:xmpp_contacts, [:xmpp_user_id, :jid], :unique)
    end

    @storage = Vines::Storage::Sql.new(:adapter => 'sqlite3', :database => DB_FILE)

    Storage::Sql::XmppUser.new(:jid => 'empty', :name => '', :password => '').save
    Storage::Sql::XmppUser.new(:jid => 'no_password', :name => '', :password => '').save
    Storage::Sql::XmppUser.new(:jid => 'clear_password', :name => '',
      :password => 'secret').save
    Storage::Sql::XmppUser.new(:jid => 'hmac_password', :name => '',
      :password => Vines::Kit.hmac('secret', 'hmac_password')).save

    full = Storage::Sql::XmppUser.new(:jid => 'full', :name => 'Tester',
      :password => Vines::Kit.hmac('secret', 'full'))
    full.contacts << Storage::Sql::XmppContact.new(:jid => 'contact1', :name => 'Contact1',
      :groups => 'Group1, Group2', :subscription => 'both')
    full.contacts << Storage::Sql::XmppContact.new(:jid => 'contact2', :name => 'Contact2',
      :groups => 'Group3, Group4', :subscription => 'both')
    full.save
  end

  def teardown
    File.delete(DB_FILE) if File.exist?(DB_FILE)
  end

  def test_init
    assert_raise(RuntimeError) { Vines::Storage::Sql.new(nil) }
    assert_raise(RuntimeError) { Vines::Storage::Sql.new({}) }
    assert_raise(RuntimeError) { Vines::Storage::Sql.new(:adapter => 'postgresql') }
    assert_nothing_raised { Vines::Storage::Sql.new('adapter' => 'sqlite3', :database => ':memory:') }
    assert_nothing_raised { Vines::Storage::Sql.new('adapter' => 'postgresql', :database => 'test', :host => 'localhost', :port => 5432) }
  end

end
