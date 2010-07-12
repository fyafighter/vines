module Vines
  module Stanza

    # Processes <body> stanzas. Used for BOSH connections
    module Body

      def body(stanza)
        log.info("Processing body stanza #{stanza}")
        if stanza.attributes['xmpp:restart']
          handle_restart
        end
      end

      def create_session(request_id, sid)
        el = REXML::Element.new('body')
        el.add_attributes({'wait' => '60', 'inactivity' => '30', 'polling' => '5', 'requests' => '2', 'hold' => '1'})
        el.add_attributes({'ack' => request_id, 'accept' => 'deflate,gzip', 'maxpause' => '120', 'sid' => @sid})
        el.add_attributes({'charsets' => 'UTF-8', 'ver' => '1.6', 'sid' => sid.to_s})
        el.add_attributes({'from' => @domain, 'xmlns' => 'http://jabber.org/protocol/httpbind'})
        features = el.add_element('stream:features')
        features.add_attributes({"xmlns:stream"=>NAMESPACES[:http_bind]})
        features.add_namespace(NAMESPACES[:client])
        mechanisms = features.add_element('mechanisms')
        mechanisms.add_namespace(NAMESPACES[:sasl])
        mechanisms.add_element('mechanism').add_text('PLAIN')
        el.to_s
      end

      def idle_body(sid, rid)
        el = REXML::Element.new('body')
        el.add_attributes({'sid'=> sid, 'rid' => rid})
        el.to_s
      end

      private

      def handle_restart
        el = REXML::Element.new('body')
        el.add_attributes({'xmlns' => NAMESPACES[:http_bind], 'xmlns:stream' => NAMESPACES[:stream]})
        features = el.add_element('stream:features')
        bind = features.add_element('bind')
        bind.add_namespace(NAMESPACES[:bind])
        @stream_state == :negotiation_complete
        @response.body = el.to_s
        send_data(el.to_s)
      end
    end
  end
end
