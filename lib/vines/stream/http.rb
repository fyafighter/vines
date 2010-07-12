require 'Thin'
require 'socket'

module Vines
  module Stream

    # BOSHStream implements the XMPP protocol for HTTP (BOSH) client-to-server (http)
    # streams. It serves connected streams using the jabber:client namespace.
    class Http < Client
      include Thin
      include Vines::Stanza::Body

      CONTENT_LENGTH = 'Content-Length'.freeze
      TRANSFER_ENCODING = 'Transfer-Encoding'.freeze
      CHUNKED_REGEXP = /\bchunked\b/i.freeze

      @@http_router = {}
      @@timer = nil

      def initialize(config)
        super
        names = %w[auth iq message presence starttls body]
        @methods = Hash[names.map{|cmd| [cmd, method(cmd)]}]
        @parser = Vines::XmlStanzaParser.new
        @storage = @config.vhosts["localhost"]
        @domain = "localhost"
        if !@@timer
          start_timer
        end
      end

      def start_timer
        log.info("Starting HTTP connection timer.")
        @@timer = EventMachine::PeriodicTimer.new(5) do
          @@http_router.each_value do |bosh_client|
            begin
              if (Time.now - bosh_client.last_activity) > 25
                if bosh_client.pending_queue_size==0
                  @@http_router.delete(bosh_client.session_id.to_s)
                end
              end
            rescue Exception => e
              log.info("Removing bosh client. #{e.to_s}")
              @@http_router.delete(bosh_client.session_id.to_s)
            end
          end
        end
      end

      def post_init
        @request = Thin::Request.new
        @response = Thin::Response.new
      end

      def receive_data(data)
        process_http_request if @request.parse(data)
      rescue InvalidRequest => e
        log.error("Invalid HTTP request" )
        log.error( e )
        close_connection
      end

      def build_response(data)
        @response.status = 200
        @response.headers["Content-Type"] = "text/xml; charset=utf-8"
        @response.headers["Server"] = "Vines"
        formated_response = "<body sid='#{@sid}' rid='#{@rid}' xmlns='http://jabber.org/protocol/httpbind'>"
        formated_response += data.to_s
        formated_response += "</body>"
        @response.body = formated_response
      end

      def send_data(data)
        if @client
          @client.remove_connection(self)
        end
        if @response.body.nil?
          build_response(data)
        end
        @response.each do |chunk|
          data = chunk
          super
        end
        close_connection_after_writing
      end

      def setup_new_client(request_id)
        @rid = request_id
        @sid = Time.now.to_i + rand(4030607)
        log.info("Setting up a new client SID: #{@sid}.")
        client = BoshClient.new(@sid, self, @config)
        @@http_router[@sid.to_s] = client
        @client = client
        router << client
        log.info("New client: #{router.size} streams are connected")
        send_data(setup_session(@response, @rid, @sid))
      end

      def setup_session(response, request_id, sid)
        response.headers["Content-Type"] = "text/xml; charset=utf-8"
        response.headers["Server"] = "Vines"
        response.body = create_session(request_id, sid)
        response
      end

      def process_http_request
        if @request.body.string.empty?
          #Respond to proxy servers' status pings
          log.info("A status request has been received.")
          send_data("online")
          return
        end

        log.info( @request.body.string )
        @parser.stanzas(@request.body.string).each do |s|
          body = Nokogiri::XML.parse(s).root
          if body.attributes['sid']
            @sid = body.attributes['sid'].value
            @rid = body.attributes['rid'].value
            @client = @@http_router[@sid.to_s]
            if not @client
              log.info("Client was not found #{@sid}")
              self.setup_new_client(@rid)
              return
            end
            restore_client
            @parser.stanzas(body.children.to_s).each {|s| process_stanza(s) }
            log.info("Processing request from #{@sid}")
            process_stanza(body.to_s)
            persist_client
          else
            self.setup_new_client(body.attributes['rid'].value)
          end
        end
      end

      def restore_client
        @user = @client.user
        @stream_state = @client.stream_state
        @last_broadcast_presence = @client.last_broadcast_presence
        @client.add_connection(self)
      end

      def persist_client()
        @client.user = @user
        @client.stream_state = @stream_state
        @client.last_broadcast_presence = @last_broadcast_presence
      end

      # Send the stanza to all recipients, stamping it with from and
      # to addresses first.
      def broadcast(stanza, recipients)
        stanza.attributes['from'] = @user.jid.to_s
        recipients.each do |recipient|
          log.info("Brodcasting to #{recipient}")
          stanza.attributes['to'] = recipient.user.jid.to_s
          recipient.send_data(stanza.to_s)
        end
      end

      def unbind
        log.info("HTTP disconnect: #{router.size} streams are connected")
        @request.async_close.succeed if @request.async_close
        @response.body.fail if @response.body.respond_to?(:fail)
      end

      def send_auth_success
        super
        @client.user = @user
      end

      private

      def remote_address
        Socket.unpack_sockaddr_in(get_peername)[1]
      end

      def enforce_rate_limit
        #do nothing
      end

      def need_content_length?(result)
        status, headers, body = result
        return false if status == -1
        return false if headers.has_key?(CONTENT_LENGTH)
        return false if (100..199).include?(status) || status == 204 || status == 304
        return false if headers.has_key?(TRANSFER_ENCODING) && headers[TRANSFER_ENCODING] =~ CHUNKED_REGEXP
        return false unless body.kind_of?(String) || body.kind_of?(Array)
        true
      end

      def set_content_length(result)
        headers, body = result[1..2]
        case body
          when String
            # See http://redmine.ruby-lang.org/issues/show/203
            headers[CONTENT_LENGTH] = (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
          when Array
            bytes = 0
            body.each do |p|
              bytes += p.respond_to?(:bytesize) ? p.bytesize : p.size
            end
            headers[CONTENT_LENGTH] = bytes.to_s
        end
      end
    end
  end
end

