class CouchDBTest < Test::Unit::TestCase
  include StorageTests

  def setup
    @db = CouchRest.database!('http://localhost:5984/testcase')
    @storage = Vines::Storage::CouchDB.new(:host => 'localhost', :port => 5984, :database => 'testcase')

    @db.save_doc({'_id' => 'empty'})
    @db.save_doc({'_id' => 'no_password', 'foo' => 'bar'})
    @db.save_doc({'_id' => 'clear_password', 'password' => 'secret'})
    @db.save_doc({'_id' => 'hmac_password', 'password' => Vines::Kit.hmac('secret', 'hmac_password')})
    @db.save_doc({
      '_id' => 'full',
      'password' => Vines::Kit.hmac('secret', 'full'),
      'name' => 'Tester',
      'roster' => {
        'contact1' => {
          'name' => 'Contact1',
          'groups' => %w(Group1 Group2)
        },
        'contact2' => {
          'name' => 'Contact2',
          'groups' => %w(Group3 Group4)
        }
      }
    })
  end

  def teardown
    @db.delete!
  end

  def test_init
    assert_raise(RuntimeError) { Vines::Storage::CouchDB.new(nil) }
    assert_raise(RuntimeError) { Vines::Storage::CouchDB.new({}) }
    assert_raise(RuntimeError) { Vines::Storage::CouchDB.new({'host' => 'localhost'}) }
    assert_raise(RuntimeError) { Vines::Storage::CouchDB.new('host' => 'localhost') }
    config = {
      'host' => 'localhost',
      'port' => '5984',
      :database => 'test'
    }
    assert_nothing_raised { Vines::Storage::CouchDB.new(config) }
    assert_nothing_raised { Vines::Storage::CouchDB.new(:host => 'localhost', 'port' => '5984', 'database' => 'test') }
  end

end
