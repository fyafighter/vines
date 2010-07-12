module Vines

  # A Config object is passed to the stream handlers to give them access
  # to server configuration information like virtual host names, storage
  # systems, etc. Basically, this represents the vines.yml configuration
  # file in memory.
  class Config

    attr_reader :vhosts

    def initialize(config)
      @listeners = init_listeners(config)
      @vhosts = init_vhosts(config)
    end

    def listeners
      @listeners.values
    end

    def vhost?(domain)
      @vhosts.key?(domain)
    end

    def s2s?(domain)
      @listeners[:s2s] && @listeners[:s2s].hosts.include?(domain)
    end

    def method_missing(name, *args)
      @listeners[name] or raise ArgumentError.new("no listener named #{name}")
    end

    private

    def init_listeners(config)
      classes = {
          :c2s => ClientListener,
          :s2s => ServerListener,
          :http => HttpListener,
          :component => ComponentListener}

      pairs = (config['listeners'] || {}).to_a.map do |name, settings|
        [name.to_sym, classes[name.to_sym].new(self, settings)]
      end
      Hash[pairs]
    end

    def init_vhosts(config)
      default_storage = create_storage(config)
      pairs = (config['hosts'] || {}).to_a.map do |name, settings|
        storage = create_storage(settings) || default_storage
        raise ArgumentError.new("storage required for #{name}") unless storage
        [name, storage]
      end
      raise ArgumentError.new("must define at least one virtual host") if pairs.empty?
      Hash[pairs]
    end

    def create_storage(config)
      return unless config && config['storage'] && config['storage']['provider']
      class_for_name(config['storage']['provider']).new(config['storage'])
    end

    def class_for_name(name)
      name.split("::").inject(Object) {|obj, piece| obj.const_get(piece) }
    end
  end

  class Listener
    include Vines::Log

    def start
      log.info("#{stream} accepting connections on #{host}:#{port}")
      EventMachine::start_server(host, port, stream, config)
    end

    private

    def init_max_stanza_size(settings, default=128 * 1024)
      @max_stanza_size = settings['max_stanza_size'] || default
      @max_stanza_size = [10000, @max_stanza_size].max # rfc 3920bis section 9.5
    end
  end

  class ClientListener < Listener
    attr_reader :host, :port, :max_stanza_size, :stream, :config,
      :max_resources_per_account

    def initialize(config, settings)
      @config = config
      @stream = Vines::Stream::Client
      @host = settings['host'] || '0.0.0.0'
      @port = settings['port'] || 5222
      @max_resources_per_account = settings['max_resources_per_account'] || 5
      init_max_stanza_size(settings, 64 * 1024)
    end
  end

  class ServerListener < Listener
    attr_reader :host, :port, :max_stanza_size, :hosts, :stream, :config

    def initialize(config, settings)
      @config = config
      @stream = Vines::Stream::Server
      @host = settings['host'] || '0.0.0.0'
      @port = settings['port'] || 5269
      init_max_stanza_size(settings)
      @hosts = settings['hosts'] || []
    end
  end

  class HttpListener < Listener
    attr_reader :host, :port, :max_stanza_size, :stream, :config

    def initialize(config, settings)
      @config = config
      @stream = Vines::Stream::Http
      @host = settings['host'] || '0.0.0.0'
      @port = settings['port'] || 5280
      init_max_stanza_size(settings)
    end
  end

  class ComponentListener < Listener
    attr_reader :host, :port, :max_stanza_size, :components, :stream, :config

    def initialize(config, settings)
      @config = config
      @stream = Vines::Stream::Component
      @host = settings['host'] || '0.0.0.0'
      @port = settings['port'] || 5280
      init_max_stanza_size(settings)
      @components = settings.clone
      %w[host port max_stanza_size].each {|k| @components.delete(k) }
    end

    def password(component)
      @components[component]
    end
  end
end
