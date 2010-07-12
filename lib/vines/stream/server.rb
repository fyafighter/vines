module Vines
module Stream

  # ServerStream implements the XMPP protocol for server-to-server (s2s)
  # streams. It serves connected streams using the jabber:server namespace.
  # This handles both accepting incoming s2s streams and initiating outbound
  # s2s streams to other servers.
  class Server < Base
    include Vines::StreamErrors
    include Vines::Stanza::Auth
    include Vines::Stanza::IQ
    include Vines::Stanza::Message
    include Vines::Stanza::Presence
    include Vines::Stanza::StartTLS

    # Starts the connection to the remote server. When the stream is
    # connected and ready to send stanzas it will yield to the callback
    # block. The callback is run on the EventMachine reactor thread. The
    # yielded stream will be nil if the remote connection failed. We need to
    # use a background thread to avoid blocking the server on DNS SRV
    # lookups.
    def self.start(config, to, from, &callback)
      op = proc do
        Resolv::DNS.open do |dns|
          dns.getresources("_xmpp-server._tcp.#{to}", Resolv::DNS::Resource::IN::SRV)
        end.sort! {|a,b| a.priority == b.priority ? b.weight <=> a.weight : a.priority <=> b.priority }
      end
      cb = proc do |srv|
        if srv.empty?
          srv << {:target => to, :port => 5269}
          class << srv.first
            def method_missing(name); self[name]; end
          end
        end
        Server.connect(config, to, from, srv, callback)
      end
      EM.defer(proc { op.call rescue [] }, cb)
    end

    def self.connect(config, to, from, srv, callback)
      if srv.empty?
        callback.call(nil)
      else
        begin
          rr = srv.shift
          opts = {:to => to, :from => from, :srv => srv, :callback => callback}
          EM.connect(rr.target.to_s, rr.port, Server, config, opts)
        rescue Exception => e
          connect(config, to, from, srv, callback)
        end
      end
    end

    attr_reader :remote_domain, :config

    def initialize(config, options={})
      @config = config
      @store = Vines::Store.new
      @stream_state = :initial
      @authentication_attempts = 0
      @remote_domain = options[:to]
      @domain = options[:from]
      @srv = options[:srv]
      @callback = options[:callback]
      @outbound = @remote_domain && @domain
      @storage = @config.vhosts[@domain] if @outbound
    end

    def post_init
      super
      send_data(stream_xml) if @outbound
    end

    def max_stanza_size
      @config.s2s.max_stanza_size
    end

    def tls_verify_peer?
      true
    end

    def ssl_verify_peer(pem)
      # EM is supposed to close the connection when this returns false
      # but it only does that for inbound connections, not when we
      # make a connection to another server.
      trusted = @store.trusted?(pem)
      close_connection unless trusted
      trusted
    end

    def ssl_handshake_completed
      close_connection unless @store.domain?(get_peer_cert, @remote_domain)
    end

    def unbind
      super
      if @outbound && @stream_state != :negotiation_complete
        Server.connect(@config, @remote_domain, @domain, @srv, @callback)
      end
    end

    private

    def stream_open(el)
      log.debug("Received stream open:\tfrom=#{@remote_addr}\tto=#{@local_addr}\n#{el}\n")
      return if @outbound
      default_ns, stream_ns, from, to, version = stream_attrs(el)
      @storage = @config.vhosts[to]
      @domain = to
      @remote_domain = from
      send_stream_header
      raise ImproperAddressing if [to, from].any? {|addr| (addr || '').empty? }
      raise HostUnknown unless @config.vhost?(to)
      raise NotAuthorized unless @config.s2s?(from)
      raise InvalidNamespace unless default_ns == NAMESPACES[:server]
      raise InvalidNamespace unless stream_ns == NAMESPACES[:stream]
    end

    # Advertise the appropriate stream features (based on the state of 
    # the stream negotiation) to the client in a new <stream:stream> header.
    def send_stream_header
      features = REXML::Element.new('stream:features')
      if @stream_state == :initial
        tls = features.add_element('starttls')
        tls.add_namespace(NAMESPACES[:tls])
        tls.add_element('required')
      elsif @stream_state == :started_tls
        mechanisms = features.add_element('mechanisms')
        mechanisms.add_namespace(NAMESPACES[:sasl])
        mechanisms.add_element('mechanism').add_text('EXTERNAL')
      elsif @stream_state == :authenticated
        @stream_state = :negotiation_complete
      end
      [stream_xml, features.to_s].each {|xml| send_data(xml) }
    end

    def stream_xml
      attrs = {
        'xmlns' => NAMESPACES[:server],
        'xmlns:stream' => NAMESPACES[:stream],
        'xml:lang' => 'en',
        'id' => Kit.uuid,
        'from' => @domain,
        'version' => '1.0',
        'to' => @remote_domain
      }
      "<stream:stream %s>" % attrs.to_a.map{|k,v| "#{k}='#{v}'"}.join(' ')
    end

    def handle_stanza(stanza)
      if %w[message iq presence].include?(stanza.name)
        to, from = %w[to from].map {|attr| Jabber::JID.new(stanza.attributes[attr] || '') }
        raise NotAuthorized unless @stream_state == :negotiation_complete
        raise ImproperAddressing if [to, from].any? {|addr| addr.domain.nil? || addr.domain.empty? }
        raise InvalidFrom unless from.domain == @remote_domain
        raise HostUnknown unless @config.vhost?(to.domain)
        @user = User.new(:jid => from)
      end
      processor(stanza).call(stanza)
    end

    def features(stanza)
      if stanza.elements['starttls']
        send_data("<starttls xmlns='urn:ietf:params:xml:ns:xmpp-tls'/>")
      elsif stanza.elements['mechanisms'] && stanza.elements['mechanisms'].namespace == NAMESPACES[:sasl]
        authz = Base64.encode64(@domain).chomp
        send_data("<auth xmlns='urn:ietf:params:xml:ns:xmpp-sasl' mechanism='EXTERNAL'>#{authz}</auth>")
      elsif stanza.elements.empty?
        @stream_state = :negotiation_complete
        @callback.call(self)
        @callback = nil
      else
        raise UnsupportedStanzaType
      end
    end

    def proceed(stanza)
      if stanza.namespace == NAMESPACES[:tls]
        start_tls(:private_key_file => tls_key_file,
          :cert_chain_file => tls_cert_file, :verify_peer => true)
        send_data(stream_xml)
      else
        raise UnsupportedStanzaType
      end
    end

    def failure(stanza)
      if [NAMESPACES[:sasl], NAMESPACES[:tls]].include?(stanza.namespace)
        close_connection
      else
        raise UnsupportedStanzaType
      end
    end

    def success(stanza)
      if stanza.namespace == NAMESPACES[:sasl]
        send_data(stream_xml)
      else
        raise UnsupportedStanzaType
      end
    end

    def processor(stanza)
      unless defined? @processors
        names = %w[auth failure features iq message presence proceed starttls success]
        @processors = Hash[names.map{|cmd| [cmd, method(cmd)]}]
      end
      raise UnsupportedStanzaType unless processor = @processors[stanza.name]
      processor
    end
  end

end
end
