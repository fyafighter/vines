module Vines
module Stream

  # ClientStream implements the XMPP protocol for client-to-server (c2s)
  # streams. It serves connected streams using the jabber:client namespace.
  class Client < Base
    include Vines::Log
    include Vines::StreamErrors
    include Vines::Stanza::Auth
    include Vines::Stanza::IQ
    include Vines::Stanza::Message
    include Vines::Stanza::Presence
    include Vines::Stanza::StartTLS

    attr_reader :user, :last_broadcast_presence, :config

    SUPPORTED_VERSIONS = [Version.new('1.0')]

    def initialize(config)
      @config = config
      @storage = nil
      @user = nil
      @requested_roster = false
      @available = false
      @unbound = false
      @last_broadcast_presence = nil
      @version = nil
      @stream_state = :initial
      @authentication_attempts = 0
      names = %w[auth iq message presence starttls]
      @methods = Hash[names.map{|cmd| [cmd, method(cmd)]}]
    end

    def max_stanza_size
      @config.c2s.max_stanza_size
    end

    def max_resources_per_account
      @config.c2s.max_resources_per_account
    end

    def unbind
      @unbound = true
      @available = false
      if authenticated?
        el = REXML::Element.new('presence')
        el.add_attribute('type', 'unavailable')
        outbound_unavailable_presence(el)
      end
      super
    end

    # Returns true if this client has properly authenticated with
    # the server.
    def authenticated?
      !@user.nil?
    end

    # A connected resource has authenticated and bound a resource
    # identifier.
    def connected?
      !@unbound && authenticated? && !@user.jid.bared?
    end

    # An available resource has sent initial presence and can
    # receive presence subscription requests.
    def available?
      @available && connected?
    end

    # An interested resource has requested its roster and can
    # receive roster pushes.
    def interested?
      @requested_roster && connected?
    end

    # Returns streams for available resources to which this user
    # has successfully subscribed.
    def available_subscribed_to_resources
      subscribed = @user.subscribed_to_contacts.map {|c| c.jid }
      router.available_resources(subscribed)
    end

    # Returns streams for available resources that are subscribed
    # to this user's presence updates.
    def available_subscribers
      subscribed = @user.subscribed_from_contacts.map {|c| c.jid }
      router.available_resources(subscribed)
    end

    private

    def handle_stanza(el)
      raise UnsupportedStanzaType unless processor = @methods[el.name]
      processor.call(el)
    end

    def stream_open(el)
      default_ns, stream_ns, from, to, version = stream_attrs(el)
      @storage = @config.vhosts[to]
      @domain = to
      @version = version ? Version.new(version) : Version.new('0.9')
      send_stream_header(from)
      raise NotAuthorized if @stream_state == :negotiation_complete
      raise HostUnknown unless @config.vhost?(to)
      raise InvalidNamespace unless default_ns == NAMESPACES[:client]
      raise InvalidNamespace unless stream_ns == NAMESPACES[:stream]
    end

    # Advertise the appropriate stream features (based on the state of 
    # the stream negotiation) to the client in a new <stream:stream> header.
    def send_stream_header(from)
      features = REXML::Element.new('stream:features')
      if @stream_state == :initial
        tls = features.add_element('starttls')
        tls.add_namespace(NAMESPACES[:tls])
        tls.add_element('required')
      elsif @stream_state == :started_tls
        mechanisms = features.add_element('mechanisms')
        mechanisms.add_namespace(NAMESPACES[:sasl])
        mechanisms.add_element('mechanism').add_text('PLAIN')
      elsif @stream_state == :authenticated
        features.add_element('bind').add_namespace(NAMESPACES[:bind])
        features.add_element('session').add_namespace(NAMESPACES[:session])
      end
      [stream_xml(from), features.to_s].each {|xml| send_data(xml) }
    end

    def stream_xml(from)
      attrs = {
        'xmlns' => NAMESPACES[:client],
        'xmlns:stream' => NAMESPACES[:stream],
        'xml:lang' => 'en',
        'id' => Kit.uuid,
        'from' => @domain
      }
      attrs['to'] = from if from

      version = @version.negotiate(Version.new('1.0'))
      attrs['version'] = version if version

      "<stream:stream %s>" % attrs.to_a.map{|k,v| "#{k}='#{v}'"}.join(' ')
    end
  end
end
end
