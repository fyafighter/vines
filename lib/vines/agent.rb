require 'session'
require 'socket'
require 'xmpp4r'
require 'xmpp4r/roster'

include Jabber

module Vines
  class Agent
    include Vines::Log
    def initialize(hostname, server, password, port=5222)
      @server = server
      @port = port
      @jid = "%s@%s" % [hostname, @server]
      log.info("Logging into %s as %s" % [server, @jid])
      @password = password
      @sessions = {}
    end

    def start
      client = Client.new(JID::new(@jid))
      client.connect
      client.auth(@password)
      client.send(Jabber::Presence.new.set_status("Available"))
      roster = Roster::Helper.new(client)
      roster.add_subscription_request_callback do |item, pres|
        log.info( "Received subscription request from #{pres.from.to_s}")
      end

      client.add_message_callback do |t|
        log.info( t.from.to_s + "> " + t.body.to_s)
        if roster[t.from]
          response = process_message(t) 
          log.info( response )
          html_response = format_response(response)
          msg = Message::new(t.from.to_s, response)
          msg.add_element(format_response(response))
          msg.type = :chat
          client.send(msg)
        else 
          log.info( "The sender is not authorized" )
        end
      end

      Thread.stop
    end

    private

    def format_response(response)
      response = response.sub("\n", "\r\n<br/>")
      log.info( response )
      html = REXML::Element::new("html")
      html.add_namespace('http://jabber.org/protocol/xhtml-im')
      body = REXML::Element::new("body")
      body.add_namespace('http://www.w3.org/1999/xhtml')
      text = REXML::Text.new(response, false, nil, true, nil, %r/.^/ )
      body.add(text)
      html.add(body)
      html
    end

    def process_message(message)
      user = message.from.to_s.split("@").first
      log.info( user )
      shell = @sessions[user]
      if shell
        log.info( "The shell exists" )
        Process.uid = shell['uid']
        stdout, stderr = shell['shell'].execute(message.body.to_s)
        return stdout
      else
        log.info( "The shell does not exist yet")
        stdout = `id -u #{user}`
        log.info( "New user session.")
        Process.uid = stdout.strip().to_i
        shell = {'uid' => stdout.strip().to_i, 'shell' => Session::Shell.new}
        @sessions[user] = shell
        stdout, stderr = shell['shell'].execute(message.body.to_s)
        return stdout
      end
    end
  end
end
