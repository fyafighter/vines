module Vines

  # A module for utility methods with no better home.
  module Kit

    # Create a hex-encoded, SHA-512 HMAC of the data, using the secret key.
    def self.hmac(key, data)
      digest = OpenSSL::Digest::Digest.new("sha512")
      OpenSSL::HMAC.hexdigest(digest, key, data)
    end

    # Generates a random uuid per rfc 4122 that's useful for including in
    # stream, iq, and other xmpp stanzas.
    def self.uuid
      bits = Array.new(128).map { rand(2) }
      hex = bits.join.to_i(2).to_s(16)
      hex += "0" * (32 - hex.length)
      hex[12] = '4'
      hex[16] = %w[8 9 a b][rand(4)]
      hex.scan(/(\w{8})(\w{4})(\w{4})(\w{4})(\w{12})/).first.join('-')
    end
  end

end
