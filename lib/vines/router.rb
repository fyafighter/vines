module Vines
  # The router tracks all stream connections to the server for
  # all clients, servers, and components. It sends stanzas to
  # the correct stream based on the 'to' attribute.
  class Router
    include Singleton

    ROUTABLE_STANZAS = %w[message iq presence]

    def initialize
      @config = nil
      @streams = Hash.new {|h,k| h[k] = [] }
      @pending = {}
    end

    %w[Client Server Component BoshClient].each do |klass|
      name = klass.split(/(?=[A-Z])/).join('_').downcase
      define_method(name + 's') do
        @streams["Vines::Stream::#{klass}"]
      end
    end

    # Returns streams for all connected resources for this JID. A
    # resource is considered connected after it has completed authentication
    # and resource binding.
    def connected_resources(jid)
      jid = Jabber::JID.new(jid) unless jid.kind_of?(Jabber::JID)
      (clients | bosh_clients).select do |stream|
        stream.connected? && jid == (jid.bared? ? stream.user.jid.bare : stream.user.jid)
      end
    end

    # Returns streams for all available resources for this JID. A
    # resource is marked available after it sends initial presence.
    # This method accepts a single JID or a list of JIDs.
    def available_resources(*jid)
      ids = jid.flatten.map {|jid| Jabber::JID.new(jid).bare }
      (clients | bosh_clients).select do |stream|
        stream.available? && ids.include?(stream.user.jid.bare)
      end
    end

    # Returns streams for all interested resources for this JID. A
    # resource is marked interested after it requests the roster.
    # This method accepts a single JID or a list of JIDs.
    def interested_resources(*jid)
      ids = jid.flatten.map {|jid| Jabber::JID.new(jid).bare }
      (clients | bosh_clients).select do |stream|
        stream.interested? && ids.include?(stream.user.jid.bare)
      end
    end

    # Add the connection to the routing table.
    def <<(connection)
      @config ||= connection.config
      @streams[connection.class.to_s] << connection
    end

    # Remove the connection from the routing table.
    def delete(connection)
      @streams[connection.class.to_s].delete(connection)
    end

    # Send the stanza to the appropriate remote server-to-server stream
    # or an external component stream.
    def route(stanza)
      to, from = %w[to from].map {|attr| Jabber::JID.new(stanza.attributes[attr]) }
      if stream = connection_to(to.domain)
        stream.send_data(stanza)
      elsif @pending.key?(to.domain)
        @pending[to.domain] << stanza
      elsif @config.s2s?(to.domain)
        @pending[to.domain] = [] << stanza
        Vines::Stream::Server.start(@config, to.domain, from.domain) do |stream|
          if stream
            @pending[to.domain].each {|s| stream.send_data(s) }
          else
            @pending[to.domain].each do |s|
              xml = StanzaErrors::RemoteServerNotFound.new(s, 'cancel').to_xml
              connected_resources(s.attributes['from']).each {|c| c.send_data(xml) }
            end
          end
          @pending.delete(to.domain)
        end
      else
        raise StanzaErrors::RemoteServerNotFound.new(stanza, 'cancel')
      end
    end

    # Returns true if this stanza should be processed locally. Returns false
    # if it's destined for a remote domain or external component.
    def local?(stanza)
      return true unless ROUTABLE_STANZAS.include?(stanza.name)
      to = stanza.attributes['to'] || ''
      to.empty? || local_jid?(to)
    end

    def local_jid?(jid)
      @config.vhost?(Jabber::JID.new(jid).domain)
    end

    # Returns the total number of streams connected to the server.
    def size
      clients.size + servers.size + components.size + bosh_clients.size
    end

    private

    def connection_to(domain)
      [components, servers].inject(nil) do |acc, streams|
        acc ? acc : streams.find {|stream| stream.remote_domain == domain }
      end
    end

  end
end
