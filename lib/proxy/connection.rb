require 'eventmachine'

module EventMachine
  module ProxyServer
    class Connection < EventMachine::Connection

      def on_data(&blk); @on_data = blk; end
      def on_response(&blk); @on_response = blk; end
      def on_finish(&blk); @on_finish = blk; end

      def initialize
        @servers = {}
      end

      def receive_data(data)
        processed = @on_data.call(data)

        if processed.is_a? Array
          data, servers = *processed

          # guard for "unbound" servers
          servers = servers.collect {|s| @servers[s]}.compact
        else
          data = processed
          servers ||= @servers.values.compact
        end

        servers.each do |s|
          s.send_data data unless data.nil?
        end
      end

      def server(name, opts)
        srv = EventMachine::connect(opts[:host], opts[:port], EventMachine::ProxyServer::Backend) do |c|
          c.name = name
          c.plexer = self
        end

        @servers[name] = srv
      end

      def relay_from_backend(name, data)
        data = @on_response.call(name, data)
        send_data data unless data.nil?
      end

      def unbind
        @servers.values.compact.each do |s|
          s.close_connection_after_writing
        end

        close_connection_after_writing
        @on_finish.call(:done) if @servers.values.compact.size.zero? if @on_finish
      end

      def unbind_backend(name)
        @servers[name] = nil
        @on_finish.call(name) if @on_finish
        close_connection_after_writing if @servers.values.compact.size.zero?
      end
    end
  end
end
