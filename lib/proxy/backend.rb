require 'eventmachine'

module EventMachine
  module ProxyServer
    class Backend < EventMachine::Connection
      attr_accessor :plexer, :data, :name

      def initialize
        @connected = EM::DefaultDeferrable.new
        @data = []
      end

      def connection_completed
        @connected.succeed
      end

      def receive_data(data)
        @data.push data
        @plexer.relay_from_backend(@name, data)
      end

      def send(data)
        @connected.callback { send_data data }
      end

      def unbind
        @plexer.unbind_backend(@name)
      end
    end
  end
end
