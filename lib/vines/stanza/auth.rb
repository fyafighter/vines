module Vines
  module Stanza
    # Processes <auth> stanzas. Supported authentication mechanisms are
    # PLAIN for c2s streams and EXTERNAL for s2s streams.
    module Auth
      MAX_AUTH_ATTEMPTS = 3
      AUTH_MECHANISMS = {
          'PLAIN' => :plain_auth,
          'EXTERNAL' => :external_auth}

      def auth(stanza)
        send_auth_fail(SaslErrors::MalformedRequest.new) and return unless stanza.text
        (name = AUTH_MECHANISMS[stanza.attributes['mechanism']]) ?
            method(name).call(stanza) :
            send_auth_fail(SaslErrors::InvalidMechanism.new)
      end

      private

      # Authenticate s2s streams by comparing their domain to
      # their SSL certificate.
      def external_auth(stanza)
        domain = Base64.decode64(stanza.text)
        cert = get_peer_cert ? OpenSSL::X509::Certificate.new(get_peer_cert) : nil
        if cert.nil? || !OpenSSL::SSL.verify_certificate_identity(cert, domain)
          send_auth_fail(SaslErrors::NotAuthorized.new)
        else
          @remote_domain = domain
          send_auth_success
        end
      end

      # Authenticate c2s streams using a username and password. Call the
      # authentication module in a separate thread to avoid blocking stanza
      # processing for other users. 
      def plain_auth(stanza)
        jid, node, password = Base64.decode64(stanza.text).split("\000")
        jid = [node, @domain].join('@') if jid.nil? || jid.empty?

        op = proc do
          begin
            log.info("Authenticating user: %s" % jid)
            @storage.authenticate(jid, password) || SaslErrors::NotAuthorized.new
          rescue Exception => e
            log.error("Failed to authenticate: #{e.to_s}")
            SaslErrors::TemporaryAuthFailure.new
          end
        end

        callback = proc do |result|
          if result.kind_of?(Exception)
            send_auth_fail(result)
          else
            @user = result
            log.info("Authentication succeeded: %s" % @user.jid)
            send_auth_success
          end
        end

        EM.defer(op, callback)
      end

      def send_auth_success
        @stream_state = :authenticated
        el = REXML::Element.new('success')
        el.add_namespace(NAMESPACES[:sasl])
        send_data(el.to_s)
        true
      end

      def send_auth_fail(condition)
        log.info("Authentication failed")
        @authentication_attempts += 1
        if @authentication_attempts >= MAX_AUTH_ATTEMPTS
          handle_error(StreamErrors::PolicyViolation.new("max authentication attempts exceeded"))
        else
          handle_error(condition)
        end
      end
    end
  end
end
