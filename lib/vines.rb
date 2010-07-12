module Vines
  VERSION = '0.1.0'

  NAMESPACES = {
    :stream      => 'http://etherx.jabber.org/streams'.freeze,
    :client      => 'jabber:client'.freeze,
    :server      => 'jabber:server'.freeze,
    :component   => 'jabber:component:accept'.freeze,
    :roster      => 'jabber:iq:roster'.freeze,
    :non_sasl    => 'jabber:iq:auth'.freeze,
    :sasl        => 'urn:ietf:params:xml:ns:xmpp-sasl'.freeze,
    :tls         => 'urn:ietf:params:xml:ns:xmpp-tls'.freeze,
    :bind        => 'urn:ietf:params:xml:ns:xmpp-bind'.freeze,
    :session     => 'urn:ietf:params:xml:ns:xmpp-session'.freeze,
    :ping        => 'urn:xmpp:ping'.freeze,
    :disco_items => 'http://jabber.org/protocol/disco#items'.freeze,
    :disco_info  => 'http://jabber.org/protocol/disco#info'.freeze,
    :http_bind   => 'http://jabber.org/protocol/httpbind'.freeze,
    :bosh        => 'urn:xmpp:xbosh'.freeze
  }.freeze

  module Log
    def log
      @@logger ||= Logger.new(STDOUT)
    end
  end
end

%w[
  rubygems
  resolv-replace
  active_record
  base64
  couchrest
  digest/sha1
  eventmachine
  logger
  net/ldap
  nokogiri
  openssl
  rexml/document
  socket
  xmpp4r
  yaml

  vines/stanza/auth
  vines/stanza/iq
  vines/stanza/message
  vines/stanza/presence
  vines/stanza/starttls
  vines/stanza/body

  vines/storage/couchdb
  vines/storage/ldap
  vines/storage/local
  vines/storage/sql

  vines/store
  vines/agent
  vines/config
  vines/daemon
  vines/error
  vines/kit
  vines/router
  vines/shell
  vines/token_bucket
  vines/user
  vines/version
  vines/xml_stanza_parser
  vines/xmpp_server

  vines/stream/parser
  vines/stream/base
  vines/stream/client
  vines/stream/component
  vines/stream/http
  vines/stream/server
  vines/stream/bosh_client

].each {|f| require f }
