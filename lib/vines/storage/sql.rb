module Vines
  module Storage

    # A storage implementation that persists data in a SQL database.
    class Sql

      class XmppUser < ActiveRecord::Base
        has_many :contacts, :class_name => 'XmppContact'
      end

      class XmppContact < ActiveRecord::Base;
      end

      def initialize(config)
        raise "Must provide a config hash" unless config
        config = Hash[config.to_a.map {|k, v| [k.to_sym, v] }]
        required = [:adapter, :database]
        required << [:host, :port] unless config[:adapter] == 'sqlite3'
        required.flatten.each {|key| raise "Must provide #{key}" unless config[key] }
        @adapter = config[:adapter]
        @host = config[:host]
        @port = config[:port]
        @database = config[:database]
        @username = config[:username]
        @password = config[:password]
      end

      # Validates a username and password against a SQL database.
      # Passwords are stored as a SHA-512 HMAC of the username for safe keeping.
      def authenticate(username, password)
        return unless username && password
        password = Vines::Kit.hmac(password, username)
        user = find_user_by_jid(username)
        (user && user.password == password) ? user : nil
      end

      def find_user_by_jid(jid)
        return unless jid
        jid = Jabber::JID.new(jid).bare.to_s
        connect
        xuser = XmppUser.find_by_jid(jid)
        return unless xuser
        user = User.new(:jid => jid, :name => xuser.name, :password => xuser.password)
        xuser.contacts.each do |contact|
          groups = contact.groups ? contact.groups.split(',').map{|g| g.strip} : []
          user.roster << Contact.new(
              :jid => contact.jid,
              :name => contact.name,
              :subscription => contact.subscription,
              :ask => contact.ask,
              :groups => groups)
        end
        user
      end

      def save_user(user)
        connect
        xuser = XmppUser.new(:jid => user.jid.bare.to_s, :name => user.name,
                             :password => user.password, :contacts => [])
        user.roster.each do |contact|
          props = contact.to_h
          props[:jid] = contact.jid.bare.to_s
          props['groups'] = props['groups'].join(',')
          xuser.contacts << XmppContact.new(props)
        end
        xuser.save
      end

      private

      def connect
        ActiveRecord::Base.establish_connection(
            :adapter => @adapter,
            :host => @host,
            :port => @port,
            :database => @database,
            :username => @username,
            :password => @password
        )
      end
    end
  end
end
