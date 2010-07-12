# Mixin methods for storage implementation test classes. The behavioral
# tests are the same regardless of implementation so share those methods
# here.
module StorageTests

  def test_authenticate
    assert_nil(@storage.authenticate(nil, nil))
    assert_nil(@storage.authenticate(nil, 'secret'))
    assert_nil(@storage.authenticate('bogus', nil))
    assert_nil(@storage.authenticate('bogus', 'secret'))
    assert_nil(@storage.authenticate('empty', 'secret'))
    assert_nil(@storage.authenticate('no_password', 'secret'))
    assert_nil(@storage.authenticate('clear_password', 'secret'))

    user = @storage.authenticate('hmac_password', 'secret')
    assert_not_nil(user)
    assert_equal('hmac_password', user.jid.to_s)

    user = @storage.authenticate('full', 'secret')
    assert_not_nil(user)
    assert_equal('Tester', user.name)
    assert_equal('full', user.jid.to_s)

    assert_equal(2, user.roster.length)
    assert_equal('contact1', user.roster[0].jid.to_s)
    assert_equal('Contact1', user.roster[0].name)
    assert_equal(2, user.roster[0].groups.length)
    assert_equal('Group1', user.roster[0].groups[0])
    assert_equal('Group2', user.roster[0].groups[1])

    assert_equal('contact2', user.roster[1].jid.to_s)
    assert_equal('Contact2', user.roster[1].name)
    assert_equal(2, user.roster[1].groups.length)
    assert_equal('Group3', user.roster[1].groups[0])
    assert_equal('Group4', user.roster[1].groups[1])
  end

  def test_find_user_by_jid
    assert_nil(@storage.find_user_by_jid(nil))

    user = @storage.find_user_by_jid('full')
    assert_not_nil(user)
    assert_equal(user.jid.to_s, 'full')

    user = @storage.find_user_by_jid(Jabber::JID.new('full'))
    assert_not_nil(user)
    assert_equal(user.jid.to_s, 'full')

    user = @storage.find_user_by_jid(Jabber::JID.new('full/resource'))
    assert_not_nil(user)
    assert_equal(user.jid.to_s, 'full')
  end

  def test_save_user
    user = User.new(:jid => 'save_user@domain.tld/resource1', :name => 'Save User', :password => 'secret')
    user.roster << Contact.new(:jid => 'contact1@domain.tld/resource2', :name => 'Contact 1')
    @storage.save_user(user)
    user = @storage.find_user_by_jid('save_user@domain.tld')
    assert_not_nil(user)
    assert_equal('save_user@domain.tld', user.jid.to_s)
    assert_equal('Save User', user.name)
    assert_equal(1, user.roster.length)
    assert_equal('contact1@domain.tld', user.roster[0].jid.to_s)
    assert_equal('Contact 1', user.roster[0].name)
  end

end
