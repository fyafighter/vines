module Vines
module Stream

  # ComponentStream implements the XMPP protocol for trusted, external
  # component (XEP-0114) streams. It serves connected streams using the
  # jabber:component:accept namespace.
  class Component < Base
    include StreamErrors

    attr_reader :remote_domain, :config

    def initialize(config)
      @config = config
      @remote_domain = nil
      @stream_id = nil
      @stream_state = :initial
    end

    def max_stanza_size
      @config.component.max_stanza_size
    end

    private

    def stream_open(el)
      default_ns, stream_ns, from, to, version = stream_attrs(el)
      send_data(stream_xml(to))
      raise NotAuthorized unless @stream_state == :initial
      raise HostUnknown unless @config.component.password(to)
      raise InvalidNamespace unless default_ns == NAMESPACES[:component]
      raise InvalidNamespace unless stream_ns == NAMESPACES[:stream]
      @remote_domain = to
      @stream_state = :waiting_handshake
    end

    def handle_stanza(stanza)
      raise NotAuthorized unless @stream_state != :initial
      if @stream_state == :waiting_handshake
        unless stanza.name == 'handshake' && stanza.get_text == secret
          raise NotAuthorized
        end
        @stream_state = :authenticated
        send_data('<handshake/>')
      else
        to = stanza.attributes['to'] || ''
        from = stanza.attributes['from'] || ''
        from = Jabber::JID.new(from)
        raise ImproperAddressing if to.empty? || from.domain != @remote_domain
        if router.local?(stanza)
          router.connected_resources(to).each do |recipient|
            recipient.send_data(stanza.to_s)
          end
        else
          router.route(stanza)
        end
      end
    end

    def secret
      Digest::SHA1.hexdigest(@stream_id + @config.component.password(@remote_domain))
    end

    def stream_xml(from)
      @stream_id = Kit.uuid
      attrs = {
        'xmlns' => NAMESPACES[:component],
        'xmlns:stream' => NAMESPACES[:stream],
        'id' => @stream_id,
        'from' => from
      }
      "<stream:stream %s>" % attrs.to_a.map{|k,v| "#{k}='#{v}'"}.join(' ')
    end
  end

end
end
