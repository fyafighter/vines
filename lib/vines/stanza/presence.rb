module Vines
  module Stanza

    module Presence
      PRESENCE_TYPES = %w[subscribe subscribed unsubscribe unsubscribed unavailable probe error]

      def presence(stanza)
        dir = (self.class == Vines::Stream::Client) ? 'outbound' : 'inbound'
        type = stanza.attributes['type']
        raise StreamErrors::NotAuthorized.new unless @stream_state == :negotiation_complete
        @last_broadcast_presence = stanza.clone unless stanza.attributes['to']

        if !type.nil? && !PRESENCE_TYPES.include?(type)
          raise StanzaErrors::BadRequest.new(stanza, 'modify')
        end
        method("#{dir}_#{type || 'broadcast'}_presence").call(stanza)
      end

      private

      def outbound_subscribe_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        router.route(stanza) unless router.local?(stanza)

        @user.request_subscription(to)
        storage.save_user(@user)

        router.interested_resources(@user.jid).each do |recipient|
          send_subscribe_roster_push(recipient, to)
        end

        inbound_subscribe_presence(stanza) if router.local?(stanza)
      end

      def inbound_subscribe_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        unless contact = storage.find_user_by_jid(to)
          auto_reply_to_subscription_request(stanza, to, 'unsubscribed')
          return
        end

        if contact.subscribed_from?(@user.jid)
          auto_reply_to_subscription_request(stanza, to, 'subscribed')
          return
        end

        # TODO Implement offline subscription request storage
        router.available_resources(to).each do |recipient|
          recipient.send_data(stanza)
        end
      end

      def outbound_subscribed_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        router.route(stanza) unless router.local?(stanza)

        @user.add_subscription_from(to)
        storage.save_user(@user)
        update_user_from_storage(@user.jid)

        router.interested_resources(@user.jid).each do |recipient|
          send_subscribed_roster_push(recipient, to, @user.contact(to).subscription)
        end

        presences = router.available_resources(@user.jid).map do |c|
          el = REXML::Element.new('presence')
          el.add_attributes({'to' => to, 'from' => c.user.jid.to_s})
          el
        end

        if router.local?(stanza)
          router.available_resources(to).each do |recipient|
            presences.each {|el| recipient.send_data(el) }
          end
        else
          presences.each {|el| router.route(el) }
        end

        inbound_subscribed_presence(stanza) if router.local?(stanza)
      end

      def inbound_subscribed_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        user = storage.find_user_by_jid(to)
        contact = user.contact(@user.jid) if user
        return unless contact && contact.can_subscribe?

        contact.subscribe_to
        storage.save_user(user)
        update_user_from_storage(user.jid)

        router.interested_resources(to).each do |recipient|
          recipient.send_data(stanza)
          send_subscribed_roster_push(recipient, @user.jid.bare, contact.subscription)
        end
      end

      def outbound_unsubscribed_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        router.route(stanza) unless router.local?(stanza)

        @user.remove_subscription_from(to)
        storage.save_user(@user)
        update_user_from_storage(@user.jid)

        if contact = @user.contact(to)
          router.interested_resources(@user.jid).each do |recipient|
            send_subscribed_roster_push(recipient, to, contact.subscription)
          end
        end

        inbound_unsubscribed_presence(stanza) if router.local?(stanza)
      end

      def inbound_unsubscribed_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        user = storage.find_user_by_jid(to)
        return unless user && user.subscribed_to?(@user.jid)

        contact = user.contact(@user.jid)
        contact.unsubscribe_to
        storage.save_user(user)
        update_user_from_storage(user.jid)

        router.interested_resources(to).each do |recipient|
          recipient.send_data(stanza)
          send_subscribed_roster_push(recipient, @user.jid.bare, contact.subscription)
        end
      end

      def outbound_unsubscribe_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        router.route(stanza) unless router.local?(stanza)

        @user.remove_subscription_to(to)
        storage.save_user(@user)
        update_user_from_storage(@user.jid)

        if contact = @user.contact(to)
          router.interested_resources(@user.jid).each do |recipient|
            send_subscribed_roster_push(recipient, to, contact.subscription)
          end
        end

        inbound_unsubscribe_presence(stanza) if router.local?(stanza)
      end

      def inbound_unsubscribe_presence(stanza)
        stanza.attributes['from'] = @user.jid.bare.to_s
        to = stamp_to(stanza)
        user = storage.find_user_by_jid(to)
        return unless user && user.subscribed_from?(@user.jid)

        contact = user.contact(@user.jid)
        contact.unsubscribe_from
        storage.save_user(user)
        update_user_from_storage(user.jid)

        router.interested_resources(to).each do |recipient|
          recipient.send_data(stanza)
          send_subscribed_roster_push(recipient, @user.jid.bare, contact.subscription)
          el = REXML::Element.new('presence')
          el.add_attributes({'from' => @user.jid.bare.to_s,
                             'to' => recipient.user.jid.to_s, 'type' => 'unavailable'})
          recipient.send_data(el)
        end
      end

      def outbound_error_presence(stanza)
        # FIXME Implement error handling
      end

      def inbound_error_presence(stanza)
        # FIXME Implement error handling
      end

      def outbound_probe_presence(stanza)
        stanza.attributes['from'] = @user.jid.to_s
        router.local?(stanza) ? inbound_probe_presence(stanza) : router.route(stanza)
      end

      def inbound_probe_presence(stanza)
        to = (stanza.attributes['to'] || '').strip
        raise StanzaErrors::BadRequest.new(stanza, 'modify') if to.empty?
        user = storage.find_user_by_jid(to)
        unless user && user.subscribed_from?(@user.jid)
          auto_reply_to_subscription_request(stanza, to, 'unsubscribed')
        else
          router.available_resources(to).each do |stream|
            el = stream.last_broadcast_presence.clone
            el.attributes['from'] = to
            el.attributes['to'] = @user.jid.to_s
            send_data(el)
          end
        end
      end

      def outbound_broadcast_presence(stanza)
        stanza.attributes['from'] = @user.jid.to_s
        to = (stanza.attributes['to'] || '').strip
        type = (stanza.attributes['type'] || '').strip
        initial = to.empty? && type.empty? && !available?

        recipients = if to.empty?
          available_subscribers
        else
          @user.subscribed_from?(to) ? router.available_resources(to) : []
        end
        broadcast(stanza, recipients + router.available_resources(@user.jid))

        if initial
          available_subscribed_to_resources.each do |stream|
            if stream.last_broadcast_presence
              el = stream.last_broadcast_presence.clone
              el.attributes['to'] = @user.jid.to_s
              el.attributes['from'] = stream.user.jid.to_s
              send_data(el)
            end
          end
          @available = true
        end

        remote = @user.subscribed_from_contacts.reject do |c|
          router.local_jid?(c.jid) ||
              (!to.empty? && c.jid.bare != Jabber::JID.new(to).bare)
        end
        remote.each do |contact|
          stanza.attributes['to'] = contact.jid.bare.to_s
          router.route(stanza)
          send_probe(contact.jid.bare) if initial
        end
      end

      def inbound_broadcast_presence(stanza)
        to = stanza.attributes['to']
        broadcast(stanza, router.available_resources(to))
      end

      def send_subscribe_roster_push(recipient, jid)
        el = REXML::Element.new('iq')
        el.add_attribute('id', Kit.uuid)
        el.add_attribute('to', recipient.user.jid.to_s)
        el.add_attribute('type', 'set')
        query = el.add_element('query', {'xmlns' => NAMESPACES[:roster]})
        query.add_element('item', {'ask' => 'subscribe', 'jid' => jid.to_s, 'subscription' => 'none'})
        recipient.send_data(el)
      end

      def outbound_unavailable_presence(stanza)
        outbound_broadcast_presence(stanza)
      end

      def inbound_unavailable_presence(stanza)
        inbound_broadcast_presence(stanza)
      end

      def send_subscribed_roster_push(recipient, jid, state)
        el = REXML::Element.new('iq')
        el.add_attribute('id', Kit.uuid)
        el.add_attribute('to', recipient.user.jid.to_s)
        el.add_attribute('type', 'set')
        query = el.add_element('query', {'xmlns' => NAMESPACES[:roster]})
        query.add_element('item', {'jid' => jid.to_s, 'subscription' => state})
        recipient.send_data(el)
      end

      def send_probe(to)
        probe = REXML::Element.new('presence')
        probe.add_attributes({'type' => 'probe', 'id' => Kit.uuid,
                              'to' => to.to_s, 'from' => @user.jid.to_s})
        router.route(probe)
      end

      def auto_reply_to_subscription_request(stanza, from, type)
        el = REXML::Element.new('presence')
        el.add_attribute('from', from)
        el.add_attribute('to', @user.jid.bare.to_s)
        el.add_attribute('type', type)
        el.add_attribute('id', stanza.attributes['id']) if stanza.attributes['id']
        send_data(el)
      end

      def stamp_to(stanza)
        to = (stanza.attributes['to'] || '').strip
        raise StanzaErrors::BadRequest.new(stanza, 'modify') if to.empty?
        to = Jabber::JID.new(to).bare.to_s
        stanza.attributes['to'] = to
      end
    end
  end
end
