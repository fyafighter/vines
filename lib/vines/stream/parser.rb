module Vines
  module Stream

    class Parser < Nokogiri::XML::SAX::Document
      include REXML

      def initialize(&block)
        @listeners, @node = Hash.new {|h, k| h[k] = []}, nil
        @parser = Nokogiri::XML::SAX::PushParser.new(self)
        instance_eval(&block) if block
      end

      [:stream_open, :stream_close, :stanza].each do |name|
        define_method(name) do |
          &block|
          @listeners[name] << block
        end
      end

      def <<(data)
        @parser << data
        self
      end

      def start_element_namespace(name, attrs=[], prefix=nil, uri=nil, ns=[])
        el = el(name, attrs, prefix, uri, ns)
        if stream?(name, uri)
          notify(:stream_open, el)
        else
          @node << el if @node
          @node = el
        end
      end

      def end_element_namespace(name, prefix=nil, uri=nil)
        if stream?(name, uri)
          notify(:stream_close)
        elsif @node != @node.root_node
          @node = @node.parent
        else
          notify(:stanza, @node)
          @node = nil
        end
      end

      def characters(chars)
        @node.add_text(chars) if @node
      end

      def cdata_block(chars)
        @node.add_text(chars) if @node
      end

      private

      def notify(msg, el=nil)
        @listeners[msg].each do |b|
          (el ? b.call(el) : b.call) rescue nil
        end
      end

      def stream?(name, uri)
        name == 'stream' && uri == 'http://etherx.jabber.org/streams'
      end

      def el(name, attrs=[], prefix=nil, uri=nil, ns=[])
        el = Element.new(name)
        attrs.each {|attr| el.add_attribute(attr.localname, attr.value) }
        ns(el, prefix, uri)
        ns.each {|prefix, uri| ns(el, prefix, uri) }
        el
      end

      def ns(el, prefix, uri)
        if prefix && uri
          el.add_namespace(prefix, uri)
        elsif uri
          el.add_namespace(uri)
        end
      end
    end

  end
end
