module Vines
  module Storage

    # A storage implementation that persists data to a CouchDB database.
    class CouchDB

      def initialize(config)
        raise "Must provide a config hash" unless config
        config = Hash[config.to_a.map {|k, v| [k.to_sym, v] }]
        [:host, :port, :database].each {|key| raise "Must provide #{key}" unless config[key] }
        @url = url(config)
      end

      def url(config)
        scheme = ['true', true].include?(config[:tls]) ? 'https' : 'http'
        if config[:username] && config[:password]
          credentials = "%s:%s@" % [config[:username], config[:password]]
        end
        "%s://%s%s:%s/%s" % [scheme, credentials, config[:host], config[:port], config[:database]]
      end

      private :url

      # Validates a username and password against a CouchDB database.
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
        db = CouchRest.database(@url)
        begin
          doc = db.get(jid)
        rescue RestClient::ResourceNotFound
          return nil
        end
        user = User.new(:jid => jid, :name => doc['name'], :password => doc['password'])
        (doc['roster'] || {}).each_pair do |jid, props|
          user.roster << Contact.new(
              :jid => jid,
              :name => props['name'],
              :subscription => props['subscription'],
              :ask => props['ask'],
              :groups => props['groups'])
        end
        user
      end

      def save_user(user)
        db = CouchRest.database(@url)
        begin
          doc = db.get(user.jid.bare.to_s)
        rescue RestClient::ResourceNotFound
          doc = {'_id' => user.jid.bare.to_s}
        end
        doc['name'] = user.name
        doc['password'] = user.password
        doc['roster'] = {}
        user.roster.each do |contact|
          doc['roster'][contact.jid.bare.to_s] = contact.to_h
        end
        db.save_doc(doc)
      end
    end
  end
end
