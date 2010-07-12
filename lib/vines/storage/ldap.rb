module Vines
  module Storage

    # A storage implementation that persists data in an LDAP database.
    class Ldap

      def initialize(config)
        @host = config['host']
        @port = config['port']
        @tls = config['tls']
        @dn = config['dn']
        @password = config['password']
        @basedn = config['basedn']
        @object_class = config['object_class']
        @user_attr = config['user_attr']
        @name_attr = config['name_attr']
      end

      # Validates a username and password by binding to the LDAP
      # instance with those credentials. If the bind succeeds,
      # the user's attributes are retrieved.
      def authenticate(username, password)
        clas = Net::LDAP::Filter.eq("objectClass", @object_class)
        uid = Net::LDAP::Filter.eq(@user_attr, username)
        filter = clas & uid
        attrs = [@name_attr, "mail"]

        ldap = connect(@dn, @password)
        entries = ldap.search(:attributes => attrs, :filter => filter)
        return unless entries && entries.size == 1

        if connect(entries.first.dn, password).bind
          name = entries.first[@name_attr].first
          User.new(:name => name, :username => username, :roster => [])
        else
          nil
        end
      end

      private

      def connect(dn, password)
        ldap = Net::LDAP.new(:host => @host, :port => @port, :base => @basedn)
        ldap.encryption(:simple_tls) if @tls
        ldap.auth(dn, password)
        ldap
      end
    end

  end
end
