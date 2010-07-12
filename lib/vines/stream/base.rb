module Vines
  module Stream

    # Base is the base class for various XMPP streams (c2s, s2s,
    # component, etc), containing behavior common to all streams
    # like rate limiting, stanza parsing, and stream error handling.
    class Base < EventMachine::Connection
      include Vines::Log

      def post_init
        router << self
        @remote_addr, @local_addr = [get_peername, get_sockname].map do |addr|
          addr ? Socket.unpack_sockaddr_in(addr)[0, 2].reverse.join(':') : 'unknown'
        end
        @bucket = TokenBucket.new(100, 10)
        @flooded = false
        @parser = Vines::Stream::Parser.new
        @parser.stream_open {|el| process_stream_open(el) }
        @parser.stream_close { process_stream_close }
        @parser.stanza {|el| process_stanza(el) }
        log.info("Stream connected:\tfrom=#{@remote_addr}\tto=#{@local_addr}")
      end

      def receive_data(data)
        @parser << data
      end

      # Send the stanza to all recipients, stamping it with from and
      # to addresses first.
      def broadcast(stanza, recipients)
        stanza.attributes['from'] = @user.jid.to_s
        recipients.each do |recipient|
          stanza.attributes['to'] = recipient.user.jid.to_s
          recipient.send_data(stanza.to_s)
        end
      end

      # Returns the storage system for the domain. If no domain is given,
      # the stream's storage mechanism is returned.
      def storage(domain=nil)
        domain ? @config.vhosts[domain] : @storage
      end

      # Reload the user's information from storage into all active
      # connections. This will sync the user's state on disk to their
      # state in memory.
      def update_user_from_storage(jid)
        jid = Jabber::JID.new(jid) unless jid.kind_of?(Jabber::JID)
        user = storage(jid.domain).find_user_by_jid(jid.bare)
        router.connected_resources(jid.bare).each {|c| c.user.update_from(user) }
      end

      def tls_cert_file
        tls_files[0]
      end

      def tls_key_file
        tls_files[1]
      end

      def tls_verify_peer?
        false
      end

      # Send the string data over the wire to this client.
      def send_data(data)
        log.debug("Sent stanza:\t\tfrom=#{@local_addr}\tto=#{@remote_addr}\n#{data}\n")
        super
      end

      def process_stanza(stanza)
        return if @flooded
        log.debug("Received stanza:\tfrom=#{@remote_addr}\tto=#{@local_addr}\n#{stanza}\n")
        begin
          enforce_rate_limit
          handle_stanza(stanza)
        rescue Exception => e
          handle_error(e)
        end
      end

      def process_stream_open(el)
        begin
          stream_open(el)
        rescue Exception => e
          handle_error(e)
        end
      end

      def process_stream_close
        close_connection
      end

      def unbind
        router.delete(self)
        log.info("Stream disconnected:\tfrom=#{@remote_addr}\tto=#{@local_addr}")
        log.info("Streams connected: #{router.size}")
      end

      private

      def handle_stanza(stanza)
        # do nothing
      end

      def stream_open(el)
        # do nothing
      end

      def enforce_rate_limit
        unless @bucket.take(1)
          @flooded = true
          raise PolicyViolation.new('rate limit exceeded')
        end
      end

      def stream_attrs(el)
        %w[xmlns xmlns:stream from to version].map {|attr| el.attributes[attr] }
      end

      def tls_files
        %w[crt key].map {|ext| File.join(VINES_ROOT, 'conf', 'certs', "#{@domain}.#{ext}") }
      end

      def handle_error(e)
        log.error(e)
        if e.kind_of?(SaslError) || e.kind_of?(StanzaError)
          send_data(e.to_xml)
        elsif e.kind_of?(StreamError)
          send_data(e.to_xml)
          send_data('</stream:stream>')
          close_connection
        else
          send_data(StreamErrors::InternalServerError.new.to_xml)
          send_data('</stream:stream>')
          close_connection
        end
      end

      def router
        Router.instance
      end
    end

  end
end
