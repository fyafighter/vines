class LocalTest < Test::Unit::TestCase
  include StorageTests

  def setup
    @storage = Vines::Storage::Local.new(:dir => '.') 

    @empty = './empty'
    File.open(@empty, 'w') {|f| f.write('') }

    @no_password = './no_password'
    File.open(@no_password, 'w') {|f| f.write('foo: bar') }

    @clear_password = './clear_password'
    File.open(@clear_password, 'w') {|f| f.write('password: secret') }

    @hmac_password = './hmac_password'
    File.open(@hmac_password, 'w') {|f| f.write("password: #{Vines::Kit.hmac('secret', 'hmac_password')}") }

    @full = './full'
    File.open(@full, 'w') do |f|
      f.puts("password: #{Vines::Kit.hmac('secret', 'full')}")
      f.puts("name: Tester")
      f.puts("roster:")
      f.puts("  contact1:")
      f.puts("    name: Contact1")
      f.puts("    groups: [Group1, Group2]")
      f.puts("  contact2:")
      f.puts("    name: Contact2")
      f.puts("    groups: [Group3, Group4]")
    end 
  end

  def teardown
    ['./save_user@domain.tld', @empty, @no_password, @clear_password, @hmac_password, @full].each do |f|
      File.delete(f) if File.exist?(f)
    end
  end

  def test_init
    assert_raise(RuntimeError) { Vines::Storage::Local.new(nil) }
    assert_raise(RuntimeError) { Vines::Storage::Local.new({}) }
    assert_raise(RuntimeError) { Vines::Storage::Local.new({'dir' => 'bogus'}) }
    assert_raise(RuntimeError) { Vines::Storage::Local.new({'dir' => '/sbin'}) }
    assert_nothing_raised { Vines::Storage::Local.new({'dir' => '.'}) }
    assert_nothing_raised { Vines::Storage::Local.new('dir' => '.') }
    assert_nothing_raised { Vines::Storage::Local.new(:dir => '.') }
  end

end
