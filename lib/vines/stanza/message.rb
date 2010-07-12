module Vines
  module Stanza

    module Message
      MESSAGE_TYPES = %w[chat error groupchat headline normal]

      def message(stanza)
        raise StreamErrors::NotAuthorized.new unless @stream_state == :negotiation_complete
        type = stanza.attributes['type']
        unless type.nil? || MESSAGE_TYPES.include?(type)
          raise StanzaErrors::BadRequest.new(stanza, 'modify')
        end

        unless router.local?(stanza)
          stanza.attributes['from'] = @user.jid.to_s
          router.route(stanza)
          return
        end

        to = (stanza.attributes['to'] || '').strip
        to = to.empty? ? @user.jid.bare : Jabber::JID.new(to)
        recipients = router.connected_resources(to)
        if recipients.empty?
          user = storage(to.domain).find_user_by_jid(to.bare.to_s)
          raise StanzaErrors::ServiceUnavailable.new(stanza, 'cancel') unless user
          # TODO Implement offline messaging storage
        else
          broadcast(stanza, recipients)
        end
      end

    end

  end
end
