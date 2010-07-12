module Vines
  # Parses completed XML stanzas out of a partially completed XML document
  # stream. This is useful for protocols like XMPP which stream XML to
  # the server and never form a completed document. The stanzas this
  # class returns can then be passed to an XML parser like REXML to do
  # a full parse into domain objects.
  #
  # This is inspired by the XMLLightweightParser class in the Openfire XMPP
  # server http://www.igniterealtime.org/projects/openfire/. We use state
  # classes to model the state machine instead of a large conditional block
  # to make the parsing less scary.
  class XmlStanzaParser

    # Creates a parser with a configurable maximum buffer size
    # (default 1MB). If a stanza is larger than this size, an error
    # is thrown and the parser instance must be thrown away.
    def initialize(max_buffer_size=1024*1024)
      @max_buffer_size = max_buffer_size
      @state = Init.new
      @stanzas = []
      @buf = ""
      @pos = 0
      @context = context
    end

    # Pass in a string of new data to be parsed and this method returns
    # a list of completed stanzas, if any. If the incoming data does not
    # contain a full stanza, it is buffered until the next time this method
    # is called.  Hopefully, the stanza will be completed with the next
    # chunk of incoming XML. If a stanza is not completed by the time
    # the internal data buffer fills up (default 1MB), an error is thrown.
    # This prevents miscreants from sending a DOS attack of garbage data.
    def stanzas(data)
      @buf << data
      raise "Stanzas must be less than #{@max_buffer_size} bytes" if (@buf.length > @max_buffer_size)
      data.each_char do |ch|
        @state = @state.handle(@context, ch)
        @pos += 1
      end
      @stanzas.slice!(0, @stanzas.length)
    end

    private

    def context
      {:depth => 0, :inside_root_tag => false, :cdata_offset => 0,
       :tail_count => 0, :head => "", :close => method(:close_stanza)}
    end

    def close_stanza
      @stanzas << @buf.slice!(0, @pos + 1).strip
      @pos = -1 # so stanzas() loop will increment to 0
      @context = context
      Init.new
    end
  end

  # Initial parser state
  class Init
    def handle(context, ch)
      if ch == '<'
        context[:depth] = 1
        return Head.new
      end
      self
    end
  end

  # State used when the root tag name is retrieved
  class Head
    def handle(context, ch)
      state = self
      if ch == ' ' || ch == '>'
        context[:head] << '>'
        context[:inside_root_tag] = true
        return (ch == '>') ? Outside.new : Inside.new
      elsif ch == '/' && !context[:head].empty?
        context[:depth] -= 1
        state = VerifyCloseTag.new
      end 
      context[:head] << ch
      state
    end
  end

  # State used when end tag is equal to the head tag
  class Tail
    def handle(context, ch)
      state = self
      # looking for the close tag
      if context[:depth] < 1 && ch == context[:head][context[:tail_count]].chr
        context[:tail_count] += 1
        if context[:tail_count] == context[:head].length
          state = context[:close].call
        end 
      else
        context[:tail_count] = 0
        state = Inside.new
      end
      state
    end
  end

  # State used when a '<' is found and we're looking for the close tag
  class PreTail
    CDATA_START = %w(< ! [ C D A T A [)

    def handle(context, ch)
      state = self

      if ch == CDATA_START[context[:cdata_offset]]
        context[:cdata_offset] += 1
        if context[:cdata_offset] == CDATA_START.length
          context[:cdata_offset] = 0
          return InsideCdata.new
        end
      else
        context[:cdata_offset] = 0
        state = Inside.new
      end

      if ch == '/'
        context[:depth] -= 1
        state = Tail.new
      elsif ch == '!'
        # ignore comments
        state = Inside.new
      else
        context[:depth] += 1
      end
      state
    end
  end

  # Parser is inside the root tag and found a '/' to check '/>'
  class VerifyCloseTag
    def handle(context, ch)
      if ch == '>'
        context[:depth] -= 1
        (context[:depth] < 1) ? context[:close].call : Outside.new
      elsif ch == '<' 
        PreTail.new
      else
        Inside.new
      end 
    end
  end

  class InsideParamValue
    def handle(context, ch)
      (ch == '"') ? Inside.new : self
    end
  end

  class InsideCdata
    CDATA_END = %w(] ] >)

    def handle(context, ch)
      if ch == CDATA_END[context[:cdata_offset]]
        context[:cdata_offset] += 1
        if context[:cdata_offset] == CDATA_END.length
          context[:cdata_offset] = 0
          return Outside.new
        end
      else
        context[:cdata_offset] = 0
      end
      self
    end
  end

  # Parser is inside the xml and looking for closing tag
  class Inside
    CDATA_START = %w(< ! [ C D A T A [)

    def handle(context, ch)
      state = self

      if ch == CDATA_START[context[:cdata_offset]]
        context[:cdata_offset] += 1
        if context[:cdata_offset] == CDATA_START.length
          context[:cdata_offset] = 0
          return InsideCdata.new
        end
      else
        context[:cdata_offset] = 0
        state = Inside.new
      end 

      if ch == '"'
        state = InsideParamValue.new
      elsif ch == '>'
        state = Outside.new
        a = ["stream:stream>", "?xml>", "flash:stream>"]
        if context[:inside_root_tag] && a.include?(context[:head])
          state = context[:close].call # found closing stream:stream
        end
        context[:inside_root_tag] = false
      elsif ch == '/'
        state = VerifyCloseTag.new
      end
      state
    end
  end

  # Parser is reading text outside of an element 
  class Outside
    def handle(context, ch)
      if ch == '<'
        context[:cdata_offset] = 1
        return PreTail.new
      end
      self
    end
  end
end
