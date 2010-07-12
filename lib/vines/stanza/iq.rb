module Vines
  module Stanza

    module IQ
      IQ_TYPES = %w[get set result error]

      def iq(stanza)
        type = stanza.attributes['type']
        unless stanza.attributes['id'] && IQ_TYPES.include?(type)
          raise StanzaErrors::BadRequest.new(stanza, 'modify')
        end
        method("#{type}_iq").call(stanza) unless route_iq(stanza)
      end

      private

      def route_iq(stanza)
        to = Jabber::JID.new((stanza.attributes['to'] || '').strip)
        return false if to.node.nil? || to.node.empty?
        raise NotAuthorized unless @stream_state == :negotiation_complete
        stanza.attributes['from'] = @user.jid.to_s
        if router.local?(stanza)
          router.available_resources(to).each do |recipient|
            recipient.send_data(stanza)
          end
        else
          router.route(stanza)
        end
        true
      end

      def get_iq(stanza)
        raise StanzaErrors::BadRequest.new(stanza, 'modify') unless stanza.elements.size == 1
        query = stanza.elements['query']
        query = query ? query.attributes['xmlns'] : nil
        vcard = stanza.elements['vCard'] ? true : false
        ping = stanza.elements["ping[@xmlns='#{NAMESPACES[:ping]}']"]
        if ping
          ping_query(stanza)
        elsif vcard
          vcard_query(stanza)
        elsif query == NAMESPACES[:roster]
          roster_query(stanza)
        elsif query == NAMESPACES[:disco_items]
          discovery_items_query(stanza)
        elsif query == NAMESPACES[:disco_info]
          discovery_info_query(stanza)
        elsif query == NAMESPACES[:non_sasl]
          # XEP-0078 says we MUST send a service-unavailable error
          # here, but Adium 1.3.10 won't login if we do that, so just
          # swallow this stanza.
          # raise StanzaErrors::ServiceUnavailable.new(stanza, 'cancel')
        else
          raise StanzaErrors::FeatureNotImplemented.new(stanza, 'cancel')
          # FIXME 3920 section 11: no to address and namespace not recognized = ServiceUnavailable 
        end
      end

      def roster_query(stanza)
        id = stanza.attributes['id']
        @requested_roster = true
        send_data(@user.to_roster_xml(id).to_s)
      end

      def ping_query(stanza)
        id = stanza.attributes['id']
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'from' => @domain, 'to' => @user.jid.to_s, 'type' => 'result'})
        send_data(el.to_s)
      end

      def discovery_items_query(stanza)
        id = stanza.attributes['id']
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'from' => @domain, 'to' => @user.jid.to_s, 'type' => 'result'})
        el.add_element('query', {'xmlns' => NAMESPACES[:disco_items]})
        send_data(el.to_s)
      end

      def discovery_info_query(stanza)
        id = stanza.attributes['id']
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'from' => @domain, 'to' => @user.jid.to_s, 'type' => 'result'})
        query = el.add_element('query', {'xmlns' => NAMESPACES[:disco_info]})
        query.add_element('feature', {'var' => NAMESPACES[:ping]})
        send_data(el.to_s)
      end

      def vcard_query(stanza)
        id = stanza.attributes['id']
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'to' => @user.jid.to_s, 'type' => 'result'})
        el.add_element('vCard', {'xmlns' => 'vcard-temp'})
        send_data(el.to_s)
      end

      def result_iq(stanza)
        # do nothing
      end

      def error_iq(stanza)
        # do nothing
      end

      def set_iq(stanza)
        raise StanzaErrors::BadRequest.new(stanza, 'modify') unless stanza.elements.size == 1
        query = stanza.elements['query']
        query = query ? query.attributes['xmlns'] : nil
        resource = stanza.elements["bind[@xmlns='#{NAMESPACES[:bind]}']"]
        session = stanza.elements["session[@xmlns='#{NAMESPACES[:session]}']"]

        if query == NAMESPACES[:roster]
          update_roster(stanza)
        elsif resource
          bind_resource(stanza)
        elsif session
          bind_session(stanza)
        else
          raise StanzaErrors::FeatureNotImplemented.new(stanza, 'cancel')
        end
      end

      # rfc 3921 section 7.2
      def valid_from?(stanza)
        from = stanza.attributes['from']
        from.nil? || [@user.jid.to_s, @user.jid.bare.to_s].include?(from)
      end

      # rfc 3921bis section 2.1.4
      def update_roster(stanza)
        return unless valid_from?(stanza)

        el = stanza.elements['query/item']
        raise StanzaErrors::BadRequest.new(stanza, 'modify') unless el && el.attributes['jid']

        if el.attributes['subscription'] == 'remove'
          remove_contact(stanza)
          return
        end

        jid = el.attributes['jid']
        raise StanzaErrors::NotAllowed.new(stanza, 'modify') if jid == @user.jid.bare.to_s
        contact = @user.contact(jid)
        unless contact
          contact = Contact.new(:jid => jid)
          @user.roster << contact
        end
        contact.name = el.attributes['name']
        contact.groups = []
        el.elements.each('group') do |group|
          contact.groups << group.text.strip
        end
        storage.save_user(@user)
        update_user_from_storage(@user.jid)
        push_roster_updates(@user.jid, contact)
        send_result_iq(stanza)
      end

      # rfc 3921bis section 2.5
      def remove_contact(stanza)
        el = stanza.elements['query/item']
        jid = el.attributes['jid']
        contact = @user.contact(jid)
        raise StanzaErrors::ItemNotFound.new(stanza, 'modify') unless contact
        jid = contact.jid

        user = storage(jid.domain).find_user_by_jid(jid) if router.local_jid?(jid)
        if user && user.contact(@user.jid)
          user.contact(@user.jid).subscription = 'none'
          user.contact(@user.jid).ask = nil
        end
        @user.remove_contact(jid)
        [user, @user].compact.each do |u|
          storage.save_user(u)
          update_user_from_storage(u.jid)
        end
        push_roster_updates(@user.jid, Contact.new(:jid => jid, :subscription => 'remove'))
        send_result_iq(stanza)

        presence = [%w[to unsubscribe], %w[from unsubscribed]].map do |meth, type|
          presence = REXML::Element.new('presence')
          presence.add_attributes({'from' => @user.jid.bare.to_s, 'to' => jid.to_s, 'type' => type})
          contact.send("subscribed_#{meth}?") ? presence : nil
        end.compact

        if router.local_jid?(jid)
          router.interested_resources(jid).each do |recipient|
            presence.each {|el| recipient.send_data(el) }
            el = REXML::Element.new('presence')
            el.add_attributes({'from' => @user.jid.bare.to_s,
                               'to' => recipient.user.jid.to_s, 'type' => 'unavailable'})
            recipient.send_data(el)
          end
          push_roster_updates(jid, Contact.new(:jid => @user.jid, :subscription => 'none'))
        else
          presence.each {|el| router.route(el) }
        end
      end

      def send_result_iq(stanza)
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => stanza.attributes['id'], 'type' => 'result'})
        send_data(el.to_s)
      end

      def push_roster_updates(to, contact)
        el = REXML::Element.new('iq')
        query = el.add_element('query', {'xmlns' => NAMESPACES[:roster]})
        query.add_element(contact.to_roster_xml)
        router.interested_resources(to).each do |recipient|
          el.add_attributes({'type' => 'set', 'id' => Kit.uuid,
                             'to' => recipient.user.jid.to_s})
          recipient.send_data(el.to_s)
        end
      end

      # Session support is deprecated but Adium requires it so
      # reply with an iq result stanza.
      def bind_session(stanza)
        id = stanza.attributes['id']
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'from' => @domain, 'type' => 'result'})
        send_data(el.to_s)
      end

      def resource_used?(resource)
        router.available_resources(@user.jid).any? do |c|
          c.user.jid.resource == resource
        end
      end

      def bind_resource(stanza)
        if router.connected_resources(@user.jid.bare).size >= max_resources_per_account
          raise StanzaErrors::ResourceConstraint.new(stanza, 'wait')
        end
        id = stanza.attributes['id']
        res = stanza.elements['bind/resource']
        resource = res ? res.text : Kit.uuid
        @user.jid.resource = resource_used?(resource) ? Kit.uuid : resource
        el = REXML::Element.new('iq')
        el.add_attributes({'id' => id, 'type' => 'result'})
        bind = el.add_element('bind', {'xmlns' => NAMESPACES[:bind]})
        id = bind.add_element('jid')
        id.add_text(@user.jid.to_s)
        send_data(el.to_s)
        send_data('<stream:features/>')
        @stream_state = :negotiation_complete
      end
    end
  end
end
