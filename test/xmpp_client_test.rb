class XMPPClientTest < Test::Unit::TestCase

  class MockConnection
    attr_reader :sent

    def initialize
      @sent = []
    end

    def clients
      []
    end

    def send_data(data)
      @sent << data
    end

    def close_connection
    end
  end

  class MockStorage
    def initialize(config)
    end

    def authenticate(username, password)
      users = {'user1@domain.tld' => 'pass1'}
      users.key?(username) && (users[username] == password)
    end

    def find_user_by_jid(jid)
    end

    def save_user(user)
    end
  end

  def test_process_stanza_errors
    conn = MockConnection.new
    config = Vines::Config.new({
      'domain.tld' => {
        'storage' => {
          'provider' => 'XMPPClientTest::MockStorage'
        }
      }
    })
    client = Vines::XMPPClient.new(conn, config)
    header = %q{
      <stream:stream to="domain.tld"
        xmlns="jabber:client"
        xmlns:stream="http://etherx.jabber.org/streams">}
    client.stream_open(header)
    assert_raises(Vines::SaslErrors::MalformedRequest) { client.process_stanza('<auth/>') }
    assert_raises(Vines::SaslErrors::MalformedRequest) { client.process_stanza('<auth/>') }
    assert_raises(Vines::StreamErrors::PolicyViolation) { client.process_stanza('<auth/>') }

    wrong_pass = Base64.encode64("user1@domain.tld\000\000wrongpass1")
    errors = {
      'bogus' => Vines::StreamErrors::XmlNotWellFormed,
      '<bogus>' => Vines::StreamErrors::XmlNotWellFormed,
      '<message></message>' => Vines::StreamErrors::NotAuthorized,
      '<presence/>' => Vines::StreamErrors::NotAuthorized,
      '<iq/>' => Vines::StanzaErrors::BadRequest,
      '<auth>tokens</auth>' => Vines::SaslErrors::InvalidMechanism,
      '<auth mechanism="bogus">tokens</auth>' => Vines::SaslErrors::InvalidMechanism,
      '<auth mechanism="PLAIN">tokens</auth>' => Vines::SaslErrors::NotAuthorized,
      "<auth mechanism='PLAIN'>#{wrong_pass}</auth>" => Vines::SaslErrors::NotAuthorized
    }
    errors.each_pair do |stanza, error|
      client = Vines::XMPPClient.new(conn, config)
      client.stream_open(header)
      assert_raises(error) { client.process_stanza(stanza) }
    end
  end

end
