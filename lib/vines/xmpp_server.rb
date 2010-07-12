module Vines

  # The main starting point for the XMPP server process. Starts the
  # EventMachine processing loop and registers the XMPP protocol handler
  # with the ports defined in the server configuration file.
  class XmppServer
    include Vines::Log

    def initialize(config)
      @config = Vines::Config.new(config)
    end

    def start
      log.info("Starting the XMPP server")
      EventMachine::run do
        @config.listeners.each {|listener| listener.start }
      end
    end
  end
end
