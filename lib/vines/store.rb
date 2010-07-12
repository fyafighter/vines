module Vines

  # An X509 certificate store that validates certificate trust chains.
  # This uses the conf/certs/*.crt files as the list of trusted root
  # CA certificates. 
  class Store
    @@certs = nil

    def initialize
      @store = OpenSSL::X509::Store.new
      certs.each {|c| @store.add_cert(c) }
    end

    def trusted?(pem)
      cert = OpenSSL::X509::Certificate.new(pem)
      trusted = @store.verify(cert)
      @store.add_cert(cert) if trusted rescue nil
      trusted
    end

    def domain?(pem, domain)
      cert = OpenSSL::X509::Certificate.new(pem)
      OpenSSL::SSL.verify_certificate_identity(cert, domain)
    end

    def certs
      unless @@certs
        pattern = /-{5}BEGIN CERTIFICATE-{5}\n.*?-{5}END CERTIFICATE-{5}\n/m
        dir = File.join(VINES_ROOT, 'conf', 'certs')
        certs = Dir[File.join(dir, '*.crt')].map {|f| File.read(f) }
        certs = certs.map {|c| c.scan(pattern) }.flatten
        certs.map! {|c| OpenSSL::X509::Certificate.new(c) }
        @@certs = certs.reject {|c| c.not_after < Time.now }
      end
      @@certs
    end

  end
end
