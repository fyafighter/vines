module Vines
  module Stanza

    module StartTLS
      def starttls(stanza)
        files = [tls_cert_file, tls_key_file].all? {|f| File.exists?(f) }
        unless files && stanza.attributes['xmlns'] == NAMESPACES[:tls]
          el = REXML::Element.new('failure')
          el.add_namespace(NAMESPACES[:tls])
          send_data(el.to_s)
          send_data('</stream:stream>')
          close_connection
        else
          @stream_state = :started_tls
          el = REXML::Element.new('proceed')
          el.add_namespace(NAMESPACES[:tls])
          send_data(el.to_s)
          start_tls(:private_key_file => tls_key_file,
                    :cert_chain_file => tls_cert_file, :verify_peer => tls_verify_peer?)
        end
      end
    end
  end
end
