module Vines

  class XmppError < Exception
    # Returns the XML element name based on the exception class name.
    # For example, Vines::BadFormat becomes bad-format.
    def element_name
      name = self.class.name.split('::').last
      name.gsub(/([A-Z])/, '-\1').downcase[1..-1]
    end
  end

  class SaslError < XmppError
    NAMESPACE = 'urn:ietf:params:xml:ns:xmpp-sasl'

    def initialize(text=nil)
      @text = text
    end

    def to_xml
      el = REXML::Element.new('failure')
      el.add_namespace(NAMESPACE)
      el.add_element(element_name)
      if @text
        txt = el.add_element('text', {'xml:lang' => 'en'})
        txt.add_text(@text)
      end
      el.to_s
    end
  end

  class StreamError < XmppError
    NAMESPACE = 'urn:ietf:params:xml:ns:xmpp-streams'

    def initialize(text=nil)
      @text = text
    end

    def to_xml
      el = REXML::Element.new('stream:error')
      el.add_element(element_name, {'xmlns' => NAMESPACE})
      if @text
        txt = el.add_element('text', {'xmlns' => NAMESPACE, 'xml:lang' => 'en'})
        txt.add_text(@text)
      end
      el.to_s
    end
  end

  class StanzaError < XmppError
    TYPES = %w[auth cancel continue modify wait]
    KINDS = %w[message presence iq]
    NAMESPACE = 'urn:ietf:params:xml:ns:xmpp-stanzas'

    def initialize(el, type, text=nil)
      raise "type must be one of: %s" % TYPES.join(', ') unless TYPES.include?(type)
      raise "stanza must be one of: %s" % KINDS.join(', ') unless KINDS.include?(el.name)
      @stanza_kind = el.name
      @id = el.attributes['id']
      @from = el.attributes['from']
      @to = el.attributes['to']
      @type = type
      @text = text
    end

    def to_xml
      el = REXML::Element.new(@stanza_kind)
      el.add_attribute('type', 'error')
      el.add_attribute('id', @id) if @id
      el.add_attribute('to', @from) if @from
      el.add_attribute('from', @to) if @to
      error = el.add_element('error', {'type' => @type})
      error.add_element(element_name, {'xmlns' => NAMESPACE})
      if @text
        txt = error.add_element('text', {'xmlns' => NAMESPACE, 'xml:lang' => 'en'})
        txt.add_text(@text)
      end
      el.to_s
    end
  end

  # rfc 3920bis section 7.4
  module SaslErrors
    class Aborted < SaslError; end
    class AccountDisabled < SaslError; end
    class CredentialsExpired < SaslError; end
    class EncryptionRequired < SaslError; end
    class IncorrectEncoding < SaslError; end
    class InvalidAuthzid < SaslError; end
    class InvalidMechanism < SaslError; end
    class MalformedRequest < SaslError; end
    class MechanismTooWeak < SaslError; end
    class NotAuthorized < SaslError; end
    class TemporaryAuthFailure < SaslError; end
    class TransitionNeeded < SaslError; end
  end

  # rfc 3920bis section 5.6.3
  module StreamErrors
    class BadFormat < StreamError; end
    class BadNamespacePrefix < StreamError; end
    class Confict < StreamError; end
    class ConnectionTimeout < StreamError; end
    class HostGone < StreamError; end
    class HostUnknown < StreamError; end
    class ImproperAddressing < StreamError; end
    class InternalServerError < StreamError; end
    class InvalidFrom < StreamError; end
    class InvalidId < StreamError; end
    class InvalidNamespace < StreamError; end
    class InvalidXml < StreamError; end
    class NotAuthorized < StreamError; end
    class PolicyViolation < StreamError; end
    class RemoteConnectionFailed < StreamError; end
    class ResourceConstraint < StreamError; end
    class RestrictedXml < StreamError; end
    class SeeOtherHost < StreamError; end
    class SystemShutdown < StreamError; end
    class UndefinedCondition < StreamError; end
    class UnsupportedEncoding < StreamError; end
    class UnsupportedFeature < StreamError; end
    class UnsupportedStanzaType < StreamError; end
    class UnsupportedVersion < StreamError; end
    class XmlNotWellFormed < StreamError; end
  end

  # rfc 3920bis section 9.3
  module StanzaErrors
    class BadRequest < StanzaError; end
    class Conflict < StanzaError; end
    class FeatureNotImplemented < StanzaError; end
    class Forbidden < StanzaError; end
    class Gone < StanzaError; end
    class InternalServerError < StanzaError; end
    class ItemNotFound < StanzaError; end
    class JidMalformed < StanzaError; end
    class NotAcceptable < StanzaError; end
    class NotAllowed < StanzaError; end
    class NotAuthorized < StanzaError; end
    class NotModified < StanzaError; end
    class PaymentRequired < StanzaError; end
    class PolicyViolation < StanzaError; end
    class RecipientUnavailable < StanzaError; end
    class Redirect < StanzaError; end
    class RegistrationRequired < StanzaError; end
    class RemoteServerNotFound < StanzaError; end
    class RemoteServerTimeout < StanzaError; end
    class ResourceConstraint < StanzaError; end
    class ServiceUnavailable < StanzaError; end
    class SubscriptionRequired < StanzaError; end
    class UndefinedCondition < StanzaError; end
    class UnexpectedRequest < StanzaError; end
  end
end
