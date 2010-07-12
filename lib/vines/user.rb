module Vines
  class User
    attr_accessor :name, :password, :roster
    attr_reader :jid

    def initialize(args={})
      @jid = to_jid(args[:jid])
      @name = args[:name]
      @password = args[:password]
      @roster = args[:roster] || []
    end

    def jid=(jid)
      @jid = to_jid(jid)
    end

    # Update this user's information from the given user object.
    def update_from(user)
      @name = user.name
      @password = user.password
      @roster = user.roster.map {|c| c.clone }
    end

    # Returns the contact with this jid or nil if not found.
    def contact(jid)
      bare = to_jid(jid).bare
      @roster.find {|c| c.jid.bare == bare }
    end

    # Returns true if the user is subscribed to this contact's
    # presence updates.
    def subscribed_to?(jid)
      c = contact(jid)
      c && c.subscribed_to?
    end

    # Returns true if the user has a presence subscription from
    # this contact. The contact is subscribed to this user's presence.
    def subscribed_from?(jid)
      c = contact(jid)
      c && c.subscribed_from?
    end

    # Removes the contact with this jid from the user's roster.
    def remove_contact(jid)
      bare = to_jid(jid).bare
      @roster.reject! {|c| c.jid.bare == bare }
    end

    # Returns a list of the contacts to which this user has
    # successfully subscribed.
    def subscribed_to_contacts
      @roster.select {|c| c.subscribed_to? }
    end

    # Returns a list of the contacts that are subscribed to
    # this user's presence updates.
    def subscribed_from_contacts
      @roster.select {|c| c.subscribed_from? }
    end

    # Update the contact's jid on this user's roster to signal that this user
    # has requested the contact's permission to received their presence updates.
    def request_subscription(jid)
      contact = contact(jid)
      unless contact
        contact = Contact.new(:jid => jid)
        @roster << contact
      end
      contact.ask = 'subscribe' if %w[none from].include?(contact.subscription)
    end

    # Add the user's jid to this contact's roster with a subscription
    # state of 'from.' This signals that this contact has approved
    # a user's subscription.
    def add_subscription_from(jid)
      contact = contact(jid)
      unless contact
        contact = Contact.new(:jid => jid)
        @roster << contact
      end
      contact.subscribe_from
    end

    def remove_subscription_to(jid)
      c = contact(jid)
      c.unsubscribe_to if c
    end

    def remove_subscription_from(jid)
      c = contact(jid)
      c.unsubscribe_from if c
    end

    # Returns this user's roster contacts as an iq query element.
    def to_roster_xml(id)
      el = REXML::Element.new('iq')
      el.add_attributes('id' => id, 'type' => 'result')
      query = el.add_element('query', {'xmlns' => 'jabber:iq:roster'})
      @roster.each do |contact|
        query.add_element(contact.to_roster_xml)
      end
      el
    end

    private

    # Convert a string jid to a JID object if needed.
    def to_jid(jid)
      return nil if jid.nil?
      jid.kind_of?(Jabber::JID) ? jid : Jabber::JID.new(jid)
    end
  end

  class Contact
    attr_accessor :name, :subscription, :ask, :groups
    attr_reader :jid

    def initialize(args={})
      @jid = to_jid(args[:jid])
      @name = args[:name]
      @subscription = args[:subscription] || 'none'
      @ask = args[:ask]
      @groups = args[:groups] || []
    end

    def jid=(jid)
      @jid = to_jid(jid)
    end

    # Returns true if this contact is in a state that allows the user
    # to subscribe to their presence updates.
    def can_subscribe?
      @ask == 'subscribe' && %w[none from].include?(@subscription)
    end

    def subscribe_to
      @subscription = (@subscription == 'none') ? 'to' : 'both'
      @ask = nil
    end

    def unsubscribe_to
      @subscription = (@subscription == 'both') ? 'from' : 'none'
    end

    def subscribe_from
      @subscription = (@subscription == 'none') ? 'from' : 'both'
      @ask = nil
    end

    def unsubscribe_from
      @subscription = (@subscription == 'both') ? 'to' : 'none'
    end

    # Returns true if the user is subscribed to this contact's
    # presence updates.
    def subscribed_to?
      %w[to both].include?(@subscription)
    end

    # Returns true if the user has a presence subscription from
    # this contact. The contact is subscribed to this user's presence.
    def subscribed_from?
      %w[from both].include?(@subscription)
    end

    # Returns a hash of this contact's attributes suitable for persisting in
    # a document store.
    def to_h
      {
        'name' => @name,
        'subscription' => @subscription,
        'ask' => @ask,
        'groups' => @groups
      }
    end

    # Returns this contact as an xmpp <item> element.
    def to_roster_xml
      el = REXML::Element.new('item') 
      el.add_attributes({'jid' => @jid.bare.to_s, 'subscription' => @subscription})
      el.add_attribute('name', @name) unless @name.nil? || @name.empty?
      @groups.each do |g|
        el.add_element('group').add_text(g)
      end
      el
    end

    private

    # Convert a string jid to a JID object if needed.
    # Roster contact JIDs are always bare, without a resource.
    def to_jid(jid)
      return nil if jid.nil?
      jid.kind_of?(Jabber::JID) ? jid.bare : Jabber::JID.new(jid).bare
    end
  end
end
