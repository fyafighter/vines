module Vines
  module Storage

    # A storage implementation that persists data to YAML files on the
    # local file system.
    class Local

      def initialize(config)
        raise "Must provide a config hash" unless config
        @dir = config['dir'] || config[:dir]
        unless @dir && File.directory?(@dir) && File.writable?(@dir)
          raise 'Must provide a writable storage directory'
        end
      end

      # Validates a username and password against a YAML file on the
      # local file system. Passwords are stored as a SHA-512 HMAC
      # of the username for safe keeping.
      def authenticate(username, password)
        return unless username && password
        password = Vines::Kit.hmac(password, username)
        user = find_user_by_jid(username)
        (user && user.password == password) ? user : nil
      end

      def find_user_by_jid(jid)
        return unless jid
        jid = Jabber::JID.new(jid).bare.to_s
        file = File.join(@dir, jid)
        return unless File.exists?(file)
        record = YAML.load_file(file)
        return unless record
        user = User.new(:jid => jid, :name => record['name'], :password => record['password'])
        (record['roster'] || {}).each_pair do |jid, props|
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
        record = {'name' => user.name, 'password' => user.password, 'roster' => {}}
        user.roster.each do |contact|
          record['roster'][contact.jid.bare.to_s] = contact.to_h
        end
        file = File.join(@dir, user.jid.bare.to_s)
        File.open(file, 'w') do |f|
          YAML.dump(record, f)
        end
      end
    end

  end
end
