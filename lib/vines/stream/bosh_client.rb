module Vines
  module Stream
    class BoshClient

      attr_accessor :session_id, :authenticated, :user, :stream_state, :connection, :config
      attr_accessor :last_activity, :last_broadcast_presence

      def initialize(session_id, connection, config)
        @config = config
        @storage = nil
        @user = nil
        @requested_roster = false
        @available = false
        @last_broadcast_presence = nil
        @version = nil
        @stream_state = :initial
        @authentication_attempts = 0
        @session_id = session_id
        @pending_connections = [connection]
      end

      def add_connection(connection)
        @pending_connections.push(connection)
        @last_activity = Time.now
      end

      def pending_queue_size
        @pending_connections.size
      end

      def send_data(data)
        if @pending_connections.size > 0
          connection = @pending_connections.first
          @last_activity = Time.now
          connection.send_data(data)
          @pending_connections.delete(connection)
        end
      end

      def remove_connection(connection)
        @last_activity = Time.now
        @pending_connections.delete(connection)
      end

      def router
        Router.instance
      end

      # Returns true if this client has properly authenticated with
      # the server.
      def authenticated?
        !@user.nil?
      end

      # A connected resource has authenticated and bound a resource
      # identifier.
      def connected?
        authenticated? && !@user.jid.bared?
      end

      # An available resource has sent initial presence and can
      # receive presence subscription requests.
      def available?
        @available && connected?
      end

      # An interested resource has requested its roster and can
      # receive roster pushes.
      def interested?
        @requested_roster && connected?
      end

      # Reload the user's information from storage into all active
      # connections. This will sync the user's state on disk to their
      # state in memory.
      def update_user_from_storage(jid)
        jid = Jabber::JID.new(jid) unless jid.kind_of?(Jabber::JID)
        user = @storage.find_user_by_jid(jid.bare)
        connected_resources(jid.bare).each {|c| c.user.update_from(user) }
      end

      def connected_resources(jid)
        router.connected_resources(jid)
      end

      def available_resources(jid=nil)
        router.available_resources(jid || @user.jid)
      end

      def interested_resources(jid=nil)
        router.interested_resources(jid || @user.jid)
      end

      # Returns streams for available resources to which this user
      # has successfully subscribed.
      def available_subscribed_to_resources
        subscribed = @user.subscribed_to_contacts.map {|c| c.jid }
        router.available_resources(subscribed)
      end

      # Returns streams for available resources that are subscribed
      # to this user's presence updates.
      def available_subscribers
        subscribed = @user.subscribed_from_contacts.map {|c| c.jid }
        router.available_resources(subscribed)
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
    end
  end
end